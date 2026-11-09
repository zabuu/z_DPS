"""Aggregation, fights, overheal, consumables, CC breaks, threat packets and the window."""
from pathlib import Path
import pytest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

SETUP = '''
STUB.units.player = {name="Zabbu", class="MAGE", hp=1000, max=1000}
STUB.units.pet = {name="Imp", class="PET"}
STUB.units.party1 = {name="Bankuu", class="PRIEST", hp=600, max=1000}
STUB.units.party2 = {name="Zqdc", class="SHAMAN", hp=900, max=900}
STUB.units.partypet1 = {name="Cat", class="PET"}
STUB.party = 2
STUB.fire("VARIABLES_LOADED")
STUB.fire("PLAYER_ENTERING_WORLD")
STUB.fire("UNIT_HEALTH", "party1")
function log(ev, line) STUB.fire(ev, line) end
function combat(on) STUB.units.player.combat = on; if on then STUB.fire("PLAYER_REGEN_DISABLED") else STUB.fire("PLAYER_REGEN_ENABLED") end end
function player(seg, name) return zDPS.Data.Segment(seg).players[name] end
'''


@pytest.fixture
def lua():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'dofile("{ROOT}/tests/wow_stub.lua")')
    lua.execute(f'STUB.load("{ROOT}")')
    lua.execute(SETUP)
    return lua


def test_fight_lifecycle_and_damage(lua):
    lua.execute('''
log("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains Elixir of the Mongoose.")   -- pre-pull, out of combat
STUB.tick(5)
assert(not zDPS.inFight)
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball crits Boar for 600. (50 resisted)")  -- starts the fight
assert(zDPS.inFight, "damage from a group member opens a fight")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball was resisted by Boar.")
log("CHAT_MSG_COMBAT_PET_HITS", "Imp hits Boar for 9.")
log("CHAT_MSG_SPELL_PET_DAMAGE", "Cat's Claw hits Boar for 40.")
log("CHAT_MSG_SPELL_PARTY_DAMAGE", "Searing Totem IV's Attack hits Boar for 25.")
log("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "Boar hits you for 7.")
log("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "Boar crits Bankuu for 70. (10 absorbed)")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Hellfire hits you for 90.")
log("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.")
log("CHAT_MSG_COMBAT_FRIENDLY_DEATH", "Bankuu dies.")
STUB.tick(10)
combat(false)
STUB.tick(1); STUB.tick(1); STUB.tick(1)
assert(not zDPS.inFight, "fight closes after two quiet ticks")
''')
    me = lua.eval('player("current", "Zabbu")')
    assert me.dmg == 909  # 600 + 300 + 9 (Imp merged); Hellfire self damage excluded
    assert me.taken == 97  # 7 + 90 self damage
    assert me.spells["Fireball"].n == 2 and me.spells["Fireball"].crit == 1 and me.spells["Fireball"].resist == 1
    assert me.spells["Fireball"].presist == 50
    assert me.spells["Imp: Melee"].v == 9
    assert lua.eval('player("current", "Bankuu")').dmg == 40  # Cat merged into Bankuu
    assert lua.eval('player("current", "Bankuu")').deaths == 1
    assert lua.eval('player("current", "Bankuu")').taken == 70
    assert lua.eval('player("current", "Bankuu")').takenSpells["Melee"].pabsorb == 10
    assert lua.eval('player("current", "Zqdc")').dmg == 25  # only shaman gets the totem
    assert lua.eval('player("current", "Bankuu")').consumables["Elixir of the Mongoose"] == 1  # pre-pull credited
    seg = lua.eval('zDPS.Data.Segment("current")')
    assert seg.target == "Boar" and seg.stop is not None
    assert lua.eval('table.getn(zDPS.Data.history)') == 1
    assert lua.eval('zDPS.Data.Segment("total")').players["Zabbu"].dmg == 909
    assert lua.eval('zDPS.Data.Duration(zDPS.Data.Segment("total"))') >= 10


def test_fight_opens_when_group_member_is_hit(lua):
    lua.execute('log("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "Boar hits Bankuu for 7.")')
    assert lua.eval('zDPS.inFight') is True
    lua.execute('''
STUB.fire("PLAYER_REGEN_ENABLED")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Hellfire hits you for 90.")
''')
    # self damage alone never opens a fight
    lua2 = lua
    assert lua2.eval('zDPS.inFight') is True  # still the same fight (ticker closes it later)


def test_overheal_uses_health_deficit(lua):
    lua.execute('''
combat(true)
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu's Flash Heal heals Bankuu for 500.")   -- deficit 400 -> 100 overheal
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu's Flash Heal heals Bankuu for 200.")   -- deficit now 0 -> all overheal
log("CHAT_MSG_SPELL_SELF_BUFF", "Your Flash Heal heals Zqdc for 100.")          -- unknown deficit: no UNIT_HEALTH yet -> 0 overheal
log("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Zqdc gains 30 health from Bankuu's Renew.")
''')
    b = lua.eval('player("current", "Bankuu")')
    assert b.heal == 730 and b.over == 300
    assert b.heals["Flash Heal"].over == 300 and b.heals["Renew"].tick == 1
    rows = lua.eval('''(function() local out = {}; zDPS.Data.metricByKey.healing.rows(zDPS.Data.Segment("current").players.Bankuu, zDPS.Data.Segment("current"), out); return out end)()''')
    assert rows.n == 2 and rows[1].name == "Flash Heal"
    assert lua.eval('zDPS.Data.metricByKey.healing.value(player("current", "Bankuu"))') == 430


def test_cc_break_dispel_interrupt(lua):
    lua.execute('''
combat(true)
log("CHAT_MSG_SPELL_SELF_DAMAGE", "You cast Polymorph on Boar.")
log("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar is afflicted by Polymorph.")
STUB.tick(2)
log("CHAT_MSG_COMBAT_PARTY_HITS", "Bankuu hits Boar for 12.")
log("CHAT_MSG_SPELL_AURA_GONE_OTHER", "Polymorph fades from Boar.")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "You cast Polymorph on Wolf.")
log("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Wolf is afflicted by Polymorph.")
STUB.tick(20)
log("CHAT_MSG_SPELL_AURA_GONE_OTHER", "Polymorph fades from Wolf.")   -- expired, nobody hit it
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu casts Dispel Magic on Zqdc.")
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu casts Dispel Magic on Zqdc.")
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu fails to dispel Zqdc's Curse of Agony.")
log("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu interrupts Boar's Heal.")
''')
    me = lua.eval('player("current", "Zabbu")')
    b = lua.eval('player("current", "Bankuu")')
    assert me.cc == 2 and me.ccs["Polymorph"] == 2
    assert b.ccbreak == 1 and b.ccbreaks["Polymorph"] == 1
    assert b.dispel == 1 and b.dispels["Dispel Magic"] == 1
    assert b.interrupt == 1 and b.interrupts["Heal"] == 1


def test_consumables_and_explosives(lua):
    lua.execute('''
combat(true)
log("CHAT_MSG_SPELL_SELF_BUFF", "Your Major Healing Potion heals you for 1200.")
log("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains 300 Mana from Bankuu's Major Mana Potion.")
log("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Goblin Sapper Charge hits Boar for 400.")
log("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Goblin Sapper Charge hits Wolf for 380.")
log("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "You gain Well Fed.")
STUB.tick(2)
log("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Goblin Sapper Charge hits Boar for 400.")
''')
    me = lua.eval('player("current", "Zabbu")')
    b = lua.eval('player("current", "Bankuu")')
    assert me.consum == 2 and me.consumables["Major Healing Potion"] == 1 and me.consumables["Well Fed"] == 1
    assert b.consum == 3 and b.consumables["Goblin Sapper Charge"] == 2 and b.consumables["Major Mana Potion"] == 1
    rows = lua.eval('''(function() local out = {}; zDPS.Data.metricByKey.consumables.rows(player("current","Bankuu"), nil, out); return out end)()''')
    assert rows.n == 2 and rows[1].name == "Goblin Sapper Charge"
    assert lua.eval('zDPS.Data.metricByKey.consumables.category("Goblin Sapper Charge")') == "Explosive"


def test_threat_packet(lua):
    lua.execute('''
STUB.units.target = {name="Boar", combat=true}
zDPS.UI.SetMetric("threat")
STUB.fire("CHAT_MSG_ADDON", "TWT", "TWTv4=Zqdc:1:12000:100:1;Zabbu:0:9000:75:0;Bankuu:0:300:2:0;", "RAID", "Zqdc")
STUB.time = STUB.time + 2
STUB.fire("CHAT_MSG_ADDON", "TWT", "TWTv4=Zqdc:1:13000:100:1;Zabbu:0:9800:75:0;#TMTv1=Boar:0x1:Zqdc:100", "RAID", "Zqdc")
''')
    rows = lua.eval('zDPS.Threat.rows')
    assert rows.n == 2 and rows[1].name == "Zqdc" and rows[1].tank is True and rows[1].value == 13000
    assert rows[2].value == 9800 and rows[2].tps == pytest.approx(400)
    # queries go out while the threat view is open, in a group and in combat
    lua.execute('STUB.units.player.combat = true; STUB.tick(1.1)')
    assert lua.eval('STUB.addon[1].prefix') == "TWT_UDTSv4" and lua.eval('STUB.addon[1].msg') == "limit=8"
    lua.execute('zDPS.UI.SetMetric("dps"); STUB.tick(1.1)')
    assert lua.eval('table.getn(STUB.addon)') == 1


def test_window_rows_breakdown_and_report(lua):
    lua.execute('''
combat(true)
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball crits Boar for 600.")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball missed Boar.")
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Frostbolt hits Boar for 100.")
log("CHAT_MSG_COMBAT_PARTY_HITS", "Bankuu hits Boar for 50.")
STUB.time = STUB.time + 10
zDPS.UI.Refresh()
''')
    f = lua.eval('zDPSFrame')
    rows = lua.eval('zDPS.UI.frame and zDPS.UI.rows')
    r1 = lua.eval('(function() local r; for i=1,50 do end; return zDPSFrame end)()')
    # level 1: two players, Zabbu first
    text = lua.eval('(function() local t={}; for i=1,zDPS.UI.visible do local f=zDPS.UI.rowFrame(i); if f.row then t[i]=f.name_text() .. "|" .. f.value_text() end end; return t end)()') if False else None
    first = lua.eval('zDPS.UI.RowAt(1)')
    assert first.name == "Zabbu" and first.text == "100 (1000)  95%"
    assert lua.eval('zDPS.UI.RowAt(2)').name == "Bankuu"
    assert lua.eval('zDPS.UI.Title()') == "DPS · Current  0:10"
    # click into Zabbu -> detail popup
    lua.execute('zDPS.UI.ClickRow(1, "LeftButton")')
    assert lua.eval('zDPSDetail:IsShown()') is True
    assert lua.eval('zDPS.Detail.frame.title:GetText()') == "Zabbu  ·  DPS"
    assert lua.eval('zDPS.Detail.frame.sub:GetText()') == "Boar  0:10"
    tiles = lua.eval('(function() local t={} for i=1,4 do t[i]=zDPS.Detail.Tiles()[i].value:GetText() end return t end)()')
    assert tiles[1] == "1000" and tiles[2] == "100" and tiles[3] == "95%"
    rows = lua.eval('(function() local t={} for i,r in ipairs(zDPS.Detail.ListRows()) do t[i]={name=r.name:GetText(), value=r.value:GetText(), sel=r.sel:IsShown(), shown=r:IsShown()} end return t end)()')
    assert rows[1].name == "Fireball" and rows[1].value == "900  90%" and rows[1].sel is True
    assert rows[2].name == "Frostbolt" and rows[3].shown is False
    assert lua.eval('zDPS.Detail.frame.right.title:GetText()') == "Fireball"
    legend = lua.eval('(function() local t={} for i,r in ipairs(zDPS.Detail.LegendRows()) do if r:IsShown() then t[r.name:GetText()]=r.value:GetText() end end return t end)()')
    assert legend["Hits"] == "1  (33%)  avg 300" and legend["Crits"] == "1  (33%)  avg 600" and legend["Missed"] == "1  (33%)"
    assert legend["Total"] == "900  (3)" and legend["Min / max"] == "300 / 600"
    # select Frostbolt
    lua.execute('this = zDPS.Detail.ListRows()[2]; this.scripts.OnClick()')
    assert lua.eval('zDPS.Detail.frame.right.title:GetText()') == "Frostbolt"
    assert lua.eval('zDPS.Detail.ListRows()[2].sel:IsShown()') is True
    # main window stays on the player list
    assert lua.eval('zDPS.UI.Title()').startswith("DPS · Current")
    # DPS rows show the total in parentheses
    assert first.text == "100 (1000)  95%"
    # damage mode shows raw numbers, total mode label
    lua.execute('zDPS.UI.SetMetric("damage"); zDPS.UI.SetMode("total")')
    assert lua.eval('zDPS.UI.Title()').startswith("Damage · Total")
    assert lua.eval('zDPS.UI.RowAt(1)').text == "1000  95%"
    lua.execute('zDPS.UI.Report("party")')
    chat = lua.eval('STUB.chat')
    msgs = [chat[i].msg for i in range(1, len(chat) + 1) if chat[i].channel == "PARTY"]
    assert msgs[0].startswith("zDPS Damage (Total") and msgs[1] == "1. Zabbu  1000  95%" and msgs[2] == "2. Bankuu  50  5%"


def test_short_numbers(lua):
    fmt = lua.eval('zDPS.UI.FormatNumber')
    assert fmt(999) == "999" and fmt(1234) == "1234" and fmt(12345) == "12.3k" and fmt(123456) == "123k" and fmt(1234567) == "1.23m"
    assert fmt(12.34) == "12.3" and fmt(0) == "0"
    lua.execute('zDPS.db.shortNumbers = false')
    assert fmt(1234567) == "1234567"


def test_reset_total_options(lua):
    lua.execute('''
zDPS.db.resetTotal = "combat"
combat(true)
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.")
combat(false); STUB.tick(1); STUB.tick(1); STUB.tick(1)
assert(zDPS.Data.Segment("total").players.Zabbu.dmg == 300)
combat(true)
''')
    assert lua.eval('zDPS.Data.Segment("total").players.Zabbu') is None
    lua.execute('''
zDPS.db.resetTotal = "group"
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.")
STUB.party = 0; STUB.units.party1 = nil; STUB.units.party2 = nil; STUB.units.partypet1 = nil
STUB.fire("PARTY_MEMBERS_CHANGED")
assert(zDPS.Data.Segment("total").players.Zabbu.dmg == 300, "leaving a group keeps the total")
STUB.party = 1; STUB.units.party1 = {name="Bankuu", class="PRIEST", hp=600, max=1000}
STUB.fire("PARTY_MEMBERS_CHANGED")
''')
    assert lua.eval('zDPS.Data.Segment("total").players.Zabbu') is None


def test_pet_summoned_after_roster_is_picked_up(lua):
    lua.execute('''
STUB.units.pet = nil
STUB.fire("PARTY_MEMBERS_CHANGED")           -- roster without a pet
assert(zDPS.roster["Imp"] == nil)
STUB.units.pet = {name="Voidwalker", class="PET"}  -- summoned, but no UNIT_PET arrives
STUB.time = STUB.time + 6
combat(true)
log("CHAT_MSG_COMBAT_PET_HITS", "Voidwalker hits Boar for 30.")
log("CHAT_MSG_SPELL_PET_DAMAGE", "Voidwalker's Torment hits Boar for 5.")
''')
    me = lua.eval('player("current", "Zabbu")')
    assert me.dmg == 35 and me.spells["Voidwalker: Melee"].v == 30 and me.spells["Voidwalker: Torment"].v == 5


def test_multiple_windows(lua):
    lua.execute('''
combat(true)
log("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.")
log("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu's Flash Heal heals Zqdc for 500.")
local w2 = zDPS.UI.AddWindow()
assert(table.getn(zDPS.UI.windows) == 2 and w2.db.metric == "damage")
zDPS.UI.SetMetric("healing", w2)
zDPS.UI.Refresh()
''')
    assert lua.eval('zDPS.UI.Title(1)').startswith("DPS · Current")
    assert lua.eval('zDPS.UI.Title(2)').startswith("Healing · Current")
    assert lua.eval('zDPS.UI.RowAt(1, 2)').name == "Bankuu" and lua.eval('zDPS.UI.RowAt(1, 1)').name == "Zabbu"
    assert lua.eval('zDPS.db.windowCount') == 2 and lua.eval('zDPS.db.windows[2].metric') == "healing"
    # closing the second window drops its settings; closing the first only hides it
    lua.execute('zDPS.UI.CloseWindow(zDPS.UI.Window(2))')
    assert lua.eval('table.getn(zDPS.UI.windows)') == 1 and lua.eval('zDPS.db.windowCount') == 1
    lua.execute('zDPS.UI.CloseWindow(zDPS.UI.Window(1))')
    assert lua.eval('table.getn(zDPS.UI.windows)') == 1 and lua.eval('zDPSFrame:IsShown()') is False
