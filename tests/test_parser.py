"""Parser: every English global string compiles and round-trips through the per-event groups."""
from pathlib import Path
import pytest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'dofile("{ROOT}/tests/wow_stub.lua")')
    lua.execute(f'STUB.load("{ROOT}")')
    lua.execute('''
STUB.units.player = {name="Zabbu", class="MAGE", hp=1000, max=1000}
STUB.units.pet = {name="Imp", class="PET"}
STUB.units.party1 = {name="Bankuu", class="PRIEST", hp=800, max=1000}
STUB.units.party2 = {name="Zqdc", class="SHAMAN", hp=900, max=900}
STUB.units.partypet1 = {name="Cat", class="PET"}
STUB.party = 2
STUB.fire("VARIABLES_LOADED")
STUB.fire("PLAYER_ENTERING_WORLD")
''')
    return lua


def parse(lua, event, line):
    kind = lua.eval('function(e, l) return (zDPS.Parser.Parse(e, l)) end')(event, line)
    rec = lua.eval('zDPS.Parser.rec')
    return kind, {k: rec[k] for k in ("s", "sp", "t", "a", "sc", "k", "crit", "periodic", "harm", "gone", "pabsorb", "pblock", "presist", "glance", "crush")}


CASES = [
    ("CHAT_MSG_COMBAT_SELF_HITS", "You hit Boar for 25.", "dmg", dict(s="Zabbu", t="Boar", a=25, sp="Melee", crit=None)),
    ("CHAT_MSG_COMBAT_SELF_HITS", "You crit Boar for 50. (3 blocked)", "dmg", dict(s="Zabbu", t="Boar", a=50, crit=1, pblock=3)),
    ("CHAT_MSG_COMBAT_PARTY_HITS", "Bankuu hits Boar for 12 Fire damage. (2 resisted) (glancing)", "dmg", dict(s="Bankuu", t="Boar", a=12, sc="Fire", presist=2, glance=1)),
    ("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "Boar hits you for 7.", "dmg", dict(s="Boar", t="Zabbu", a=7)),
    ("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "Boar crits you for 70. (10 absorbed)", "dmg", dict(s="Boar", t="Zabbu", a=70, crit=1, pabsorb=10)),
    ("CHAT_MSG_COMBAT_SELF_MISSES", "You miss Boar.", "miss", dict(s="Zabbu", t="Boar", k="miss", sp="Melee")),
    ("CHAT_MSG_COMBAT_SELF_MISSES", "You attack. Boar dodges.", "miss", dict(t="Boar", k="dodge")),
    ("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES", "Boar attacks. You parry.", "miss", dict(s="Boar", t="Zabbu", k="parry")),
    ("CHAT_MSG_COMBAT_PARTY_MISSES", "Bankuu misses Boar.", "miss", dict(s="Bankuu", t="Boar", k="miss")),
    ("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES", "Boar misses Bankuu.", "miss", dict(s="Boar", t="Bankuu", k="miss")),
    ("CHAT_MSG_COMBAT_PARTY_MISSES", "Bankuu attacks but Boar is immune.", "miss", dict(s="Bankuu", t="Boar", k="immune")),
    ("CHAT_MSG_COMBAT_PARTY_MISSES", "Bankuu attacks. Boar absorbs all the damage.", "miss", dict(s="Bankuu", t="Boar", k="absorb")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Boar for 300.", "dmg", dict(s="Zabbu", sp="Fireball", t="Boar", a=300)),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball crits Boar for 600. (50 resisted)", "dmg", dict(sp="Fireball", a=600, crit=1, presist=50)),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Frostbolt hits Boar for 200 Frost damage.", "dmg", dict(sp="Frostbolt", a=200, sc="Frost")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Hellfire hits you for 90.", "dmg", dict(s="Zabbu", t="Zabbu", sp="Hellfire", a=90)),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Smite hits Boar for 100.", "dmg", dict(s="Bankuu", sp="Smite", t="Boar", a=100)),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Holy Fire crits Boar for 400 Holy damage.", "dmg", dict(s="Bankuu", sp="Holy Fire", t="Boar", a=400, sc="Holy", crit=1)),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Zqdc's Hunter's Mark hits Boar for 1.", "dmg", dict(s="Zqdc", sp="Hunter's Mark", t="Boar", a=1)),
    ("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "Boar's Gore hits you for 55.", "dmg", dict(s="Boar", sp="Gore", t="Zabbu", a=55)),
    ("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "Grik'nir the Cold's Frostbolt crits you for 155 Frost damage.", "dmg", dict(s="Grik'nir the Cold", sp="Frostbolt", t="Zabbu", a=155, crit=1)),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball missed Boar.", "miss", dict(sp="Fireball", t="Boar", k="miss")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball was resisted by Boar.", "miss", dict(sp="Fireball", t="Boar", k="resist")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Smite was resisted by Boar.", "miss", dict(s="Bankuu", sp="Smite", t="Boar", k="resist")),
    ("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "Boar's Gore was dodged.", "miss", dict(s="Boar", sp="Gore", t="Zabbu", k="dodge")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Sinister Strike is parried by Boar.", "miss", dict(s="Bankuu", sp="Sinister Strike", t="Boar", k="parry")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Mind Blast is absorbed by Boar.", "miss", dict(s="Bankuu", sp="Mind Blast", t="Boar", k="absorb")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Polymorph failed. Boar is immune.", "miss", dict(sp="Polymorph", t="Boar", k="immune")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu's Fireball fails. Boar is immune.", "miss", dict(s="Bankuu", sp="Fireball", t="Boar", k="immune")),
    ("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar suffers 30 Fire damage from your Immolate.", "dmg", dict(s="Zabbu", sp="Immolate", t="Boar", a=30, sc="Fire", periodic=1)),
    ("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar suffers 20 Shadow damage from Bankuu's Shadow Word: Pain.", "dmg", dict(s="Bankuu", sp="Shadow Word: Pain", t="Boar", a=20, periodic=1)),
    ("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "You suffer 15 Nature damage from Boar's Poison.", "dmg", dict(s="Boar", sp="Poison", t="Zabbu", a=15, periodic=1)),
    ("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains 50 health from Zqdc's Rejuvenation.", "heal", dict(s="Zqdc", sp="Rejuvenation", t="Bankuu", a=50, periodic=1)),
    ("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "You gain 40 health from your Rejuvenation.", "heal", dict(s="Zabbu", sp="Rejuvenation", t="Zabbu", a=40, periodic=1)),
    ("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "You gain 20 Mana from Bankuu's Mana Spring.", "power", dict(s="Bankuu", sp="Mana Spring", t="Zabbu", a=20)),
    ("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains 300 Mana from Bankuu's Major Mana Potion.", "power", dict(s="Bankuu", sp="Major Mana Potion", t="Bankuu", a=300)),
    ("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains Elixir of the Mongoose.", "aura", dict(t="Bankuu", sp="Elixir of the Mongoose", harm=None)),
    ("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "You gain Power Word: Fortitude.", "aura", dict(t="Zabbu", sp="Power Word: Fortitude")),
    ("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "Bankuu gains Inner Fire (20).", "aura", dict(t="Bankuu", sp="Inner Fire", a=20)),
    ("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar is afflicted by Polymorph.", "aura", dict(t="Boar", sp="Polymorph", harm=1)),
    ("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Boar is afflicted by Sunder Armor (3).", "aura", dict(t="Boar", sp="Sunder Armor", a=3, harm=1)),
    ("CHAT_MSG_SPELL_AURA_GONE_OTHER", "Polymorph fades from Boar.", "aura", dict(t="Boar", sp="Polymorph", gone=1)),
    ("CHAT_MSG_SPELL_AURA_GONE_SELF", "Frost Armor fades from you.", "aura", dict(t="Zabbu", sp="Frost Armor", gone=1)),
    ("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu's Flash Heal heals Zqdc for 500.", "heal", dict(s="Bankuu", sp="Flash Heal", t="Zqdc", a=500)),
    ("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu's Greater Heal critically heals Zabbu for 900.", "heal", dict(s="Bankuu", sp="Greater Heal", t="Zabbu", a=900, crit=1)),
    ("CHAT_MSG_SPELL_SELF_BUFF", "Your Flash Heal heals you for 300.", "heal", dict(s="Zabbu", sp="Flash Heal", t="Zabbu", a=300)),
    ("CHAT_MSG_SPELL_SELF_BUFF", "Your Healing Potion heals you for 400.", "heal", dict(s="Zabbu", sp="Healing Potion", t="Zabbu", a=400)),
    ("CHAT_MSG_SPELL_SELF_BUFF", "Your Flash Heal heals Bankuu for 350.", "heal", dict(s="Zabbu", sp="Flash Heal", t="Bankuu", a=350)),
    ("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu casts Dispel Magic on Zqdc.", "cast", dict(s="Bankuu", sp="Dispel Magic", t="Zqdc")),
    ("CHAT_MSG_SPELL_SELF_BUFF", "You cast Dispel Magic on Bankuu.", "cast", dict(s="Zabbu", sp="Dispel Magic", t="Bankuu")),
    ("CHAT_MSG_SPELL_SELF_BUFF", "You cast Arcane Intellect on yourself.", "cast", dict(s="Zabbu", sp="Arcane Intellect", t="Zabbu")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "You cast Polymorph on Boar.", "cast", dict(s="Zabbu", sp="Polymorph", t="Boar")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu performs Sap on Boar.", "cast", dict(s="Bankuu", sp="Sap", t="Boar")),
    ("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu casts Prayer of Healing.", "cast", dict(s="Bankuu", sp="Prayer of Healing")),
    ("CHAT_MSG_SPELL_PARTY_BUFF", "Bankuu fails to dispel Zqdc's Curse of Agony.", "dispelfail", dict(s="Bankuu", t="Zqdc", sp="Curse of Agony")),
    ("CHAT_MSG_SPELL_SELF_DAMAGE", "You interrupt Boar's Heal.", "interrupt", dict(s="Zabbu", t="Boar", sp="Heal")),
    ("CHAT_MSG_SPELL_PARTY_DAMAGE", "Bankuu interrupts Boar's Heal.", "interrupt", dict(s="Bankuu", t="Boar", sp="Heal")),
    ("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Boar dies.", "death", dict(t="Boar")),
    ("CHAT_MSG_COMBAT_FRIENDLY_DEATH", "Bankuu dies.", "death", dict(t="Bankuu")),
    ("CHAT_MSG_COMBAT_FRIENDLY_DEATH", "You die.", "death", dict(t="Zabbu")),
    ("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "You reflect 10 Nature damage to Boar.", "dmg", dict(s="Zabbu", t="Boar", a=10, sc="Nature")),
    ("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS", "Zqdc reflects 12 Nature damage to Boar.", "dmg", dict(s="Zqdc", t="Boar", a=12)),
    ("CHAT_MSG_SPELL_PET_DAMAGE", "Cat's Claw hits Boar for 40.", "dmg", dict(s="Cat", sp="Claw", t="Boar", a=40)),
    ("CHAT_MSG_COMBAT_PET_HITS", "Imp hits Boar for 9.", "dmg", dict(s="Imp", t="Boar", a=9, sp="Melee")),
]


@pytest.fixture(scope="module")
def lua():
    return runtime()


@pytest.mark.parametrize("event,line,kind,expect", CASES, ids=[c[1] for c in CASES])
def test_lines(lua, event, line, kind, expect):
    got_kind, rec = parse(lua, event, line)
    assert got_kind == kind, (line, rec)
    for key, value in expect.items():
        assert rec[key] == value, (key, rec)


def test_unhandled_lines_return_nil(lua):
    kind, _ = parse(lua, "CHAT_MSG_SPELL_SELF_DAMAGE", "You begin to cast Fireball.")
    assert kind is None
    kind, _ = parse(lua, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 100 experience.")
    assert kind is None


def test_all_specs_compiled(lua):
    count = lua.eval('zDPS.Parser.count')
    assert count >= 120, count
