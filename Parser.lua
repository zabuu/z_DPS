-- zDPS: combat log parser. Global strings are compiled once into anchored Lua
-- patterns; each event only tries the small group of patterns that can appear
-- on that event. No tables or strings are created per log line.
local Z = zDPS
local P = {}
Z.Parser = P

local find, gsub, getn, tonumber = string.find, string.gsub, table.getn, tonumber

-- English fallbacks; the client's own global string wins when present.
local EN = {
  COMBATHITSELFOTHER="You hit %s for %d.", COMBATHITCRITSELFOTHER="You crit %s for %d.",
  COMBATHITOTHEROTHER="%s hits %s for %d.", COMBATHITCRITOTHEROTHER="%s crits %s for %d.",
  COMBATHITOTHERSELF="%s hits you for %d.", COMBATHITCRITOTHERSELF="%s crits you for %d.",
  COMBATHITSCHOOLSELFOTHER="You hit %s for %d %s damage.", COMBATHITCRITSCHOOLSELFOTHER="You crit %s for %d %s damage.",
  COMBATHITSCHOOLOTHEROTHER="%s hits %s for %d %s damage.", COMBATHITCRITSCHOOLOTHEROTHER="%s crits %s for %d %s damage.",
  COMBATHITSCHOOLOTHERSELF="%s hits you for %d %s damage.", COMBATHITCRITSCHOOLOTHERSELF="%s crits you for %d %s damage.",
  MISSEDSELFOTHER="You miss %s.", MISSEDOTHEROTHER="%s misses %s.", MISSEDOTHERSELF="%s misses you.",
  VSDODGESELFOTHER="You attack. %s dodges.", VSDODGEOTHEROTHER="%s attacks. %s dodges.", VSDODGEOTHERSELF="%s attacks. You dodge.",
  VSPARRYSELFOTHER="You attack. %s parries.", VSPARRYOTHEROTHER="%s attacks. %s parries.", VSPARRYOTHERSELF="%s attacks. You parry.",
  VSBLOCKSELFOTHER="You attack. %s blocks.", VSBLOCKOTHEROTHER="%s attacks. %s blocks.", VSBLOCKOTHERSELF="%s attacks. You block.",
  VSEVADESELFOTHER="You attack. %s evades.", VSEVADEOTHEROTHER="%s attacks. %s evades.",
  VSIMMUNESELFOTHER="You attack but %s is immune.", VSIMMUNEOTHEROTHER="%s attacks but %s is immune.", VSIMMUNEOTHERSELF="%s attacks but you are immune.",
  VSABSORBSELFOTHER="You attack. %s absorbs all the damage.", VSABSORBOTHEROTHER="%s attacks. %s absorbs all the damage.", VSABSORBOTHERSELF="%s attacks. You absorb all the damage.",
  SPELLLOGSELFSELF="Your %s hits you for %d.", SPELLLOGCRITSELFSELF="Your %s crits you for %d.",
  SPELLLOGSCHOOLSELFSELF="Your %s hits you for %d %s damage.", SPELLLOGCRITSCHOOLSELFSELF="Your %s crits you for %d %s damage.",
  SPELLLOGOTHERSELF="%s's %s hits you for %d.", SPELLLOGCRITOTHERSELF="%s's %s crits you for %d.",
  SPELLLOGSCHOOLOTHERSELF="%s's %s hits you for %d %s damage.", SPELLLOGCRITSCHOOLOTHERSELF="%s's %s crits you for %d %s damage.",
  SPELLLOGSELFOTHER="Your %s hits %s for %d.", SPELLLOGCRITSELFOTHER="Your %s crits %s for %d.",
  SPELLLOGSCHOOLSELFOTHER="Your %s hits %s for %d %s damage.", SPELLLOGCRITSCHOOLSELFOTHER="Your %s crits %s for %d %s damage.",
  SPELLLOGOTHEROTHER="%s's %s hits %s for %d.", SPELLLOGCRITOTHEROTHER="%s's %s crits %s for %d.",
  SPELLLOGSCHOOLOTHEROTHER="%s's %s hits %s for %d %s damage.", SPELLLOGCRITSCHOOLOTHEROTHER="%s's %s crits %s for %d %s damage.",
  SPELLMISSOTHERSELF="%s's %s missed you.", SPELLMISSSELFOTHER="Your %s missed %s.", SPELLMISSOTHEROTHER="%s's %s missed %s.",
  SPELLRESISTOTHERSELF="%s's %s was resisted.", SPELLRESISTSELFOTHER="Your %s was resisted by %s.", SPELLRESISTOTHEROTHER="%s's %s was resisted by %s.",
  SPELLDODGEDOTHERSELF="%s's %s was dodged.", SPELLDODGEDSELFOTHER="Your %s was dodged by %s.", SPELLDODGEDOTHEROTHER="%s's %s was dodged by %s.",
  SPELLPARRIEDOTHERSELF="%s's %s was parried.", SPELLPARRIEDSELFOTHER="Your %s is parried by %s.", SPELLPARRIEDOTHEROTHER="%s's %s is parried by %s.",
  SPELLBLOCKEDOTHERSELF="%s's %s was blocked.", SPELLBLOCKEDSELFOTHER="Your %s was blocked by %s.", SPELLBLOCKEDOTHEROTHER="%s's %s was blocked by %s.",
  SPELLEVADEDSELFOTHER="Your %s was evaded by %s.", SPELLEVADEDOTHEROTHER="%s's %s was evaded by %s.",
  SPELLIMMUNEOTHERSELF="%s's %s fails. You are immune.", SPELLIMMUNESELFOTHER="Your %s failed. %s is immune.", SPELLIMMUNEOTHEROTHER="%s's %s fails. %s is immune.",
  SPELLLOGABSORBOTHERSELF="You absorb %s's %s.", SPELLLOGABSORBSELFOTHER="Your %s is absorbed by %s.", SPELLLOGABSORBOTHEROTHER="%s's %s is absorbed by %s.",
  SPELLREFLECTSELFOTHER="Your %s is reflected back by %s.", SPELLREFLECTOTHERSELF="You reflect %s's %s.", SPELLREFLECTOTHEROTHER="%s's %s is reflected back by %s.",
  PERIODICAURADAMAGESELFSELF="You suffer %d %s damage from your %s.", PERIODICAURADAMAGEOTHERSELF="You suffer %d %s damage from %s's %s.",
  PERIODICAURADAMAGESELFOTHER="%s suffers %d %s damage from your %s.", PERIODICAURADAMAGEOTHEROTHER="%s suffers %d %s damage from %s's %s.",
  PERIODICAURAHEALSELFSELF="You gain %d health from your %s.", PERIODICAURAHEALOTHERSELF="You gain %d health from %s's %s.",
  PERIODICAURAHEALSELFOTHER="%s gains %d health from your %s.", PERIODICAURAHEALOTHEROTHER="%s gains %d health from %s's %s.",
  HEALEDSELFSELF="Your %s heals you for %d.", HEALEDCRITSELFSELF="Your %s critically heals you for %d.",
  HEALEDOTHERSELF="%s's %s heals you for %d.", HEALEDCRITOTHERSELF="%s's %s critically heals you for %d.",
  HEALEDSELFOTHER="Your %s heals %s for %d.", HEALEDCRITSELFOTHER="Your %s critically heals %s for %d.",
  HEALEDOTHEROTHER="%s's %s heals %s for %d.", HEALEDCRITOTHEROTHER="%s's %s critically heals %s for %d.",
  DAMAGESHIELDSELFOTHER="You reflect %d %s damage to %s.", DAMAGESHIELDOTHERSELF="%s reflects %d %s damage to you.", DAMAGESHIELDOTHEROTHER="%s reflects %d %s damage to %s.",
  AURAAPPLICATIONADDEDSELFHELPFUL="You gain %s (%d).", AURAAPPLICATIONADDEDSELFHARMFUL="You are afflicted by %s (%d).",
  AURAAPPLICATIONADDEDOTHERHELPFUL="%s gains %s (%d).", AURAAPPLICATIONADDEDOTHERHARMFUL="%s is afflicted by %s (%d).",
  AURAADDEDSELFHELPFUL="You gain %s.", AURAADDEDSELFHARMFUL="You are afflicted by %s.",
  AURAADDEDOTHERHELPFUL="%s gains %s.", AURAADDEDOTHERHARMFUL="%s is afflicted by %s.",
  AURAREMOVEDSELF="%s fades from you.", AURAREMOVEDOTHER="%s fades from %s.",
  AURADISPELSELF="Your %s is removed.", AURADISPELOTHER="%s's %s is removed.",
  SIMPLECASTSELFSELF="You cast %s on yourself.", SIMPLECASTSELFOTHER="You cast %s on %s.",
  SIMPLECASTOTHERSELF="%s casts %s on you.", SIMPLECASTOTHEROTHER="%s casts %s on %s.",
  SIMPLEPERFORMSELFOTHER="You perform %s on %s.", SIMPLEPERFORMOTHERSELF="%s performs %s on you.", SIMPLEPERFORMOTHEROTHER="%s performs %s on %s.",
  SPELLCASTGOSELF="You cast %s.", SPELLCASTGOOTHER="%s casts %s.", SPELLPERFORMGOSELF="You perform %s.", SPELLPERFORMGOOTHER="%s performs %s.",
  DISPELFAILEDSELFSELF="You fail to dispel your %s.", DISPELFAILEDSELFOTHER="You fail to dispel %s's %s.",
  DISPELFAILEDOTHERSELF="%s fails to dispel your %s.", DISPELFAILEDOTHEROTHER="%s fails to dispel %s's %s.",
  SPELLINTERRUPTSELFOTHER="You interrupt %s's %s.", SPELLINTERRUPTOTHERSELF="%s interrupts your %s.", SPELLINTERRUPTOTHEROTHER="%s interrupts %s's %s.",
  POWERGAINSELFSELF="You gain %d %s from your %s.", POWERGAINOTHERSELF="You gain %d %s from %s's %s.",
  POWERGAINSELFOTHER="%s gains %d %s from your %s.", POWERGAINOTHEROTHER="%s gains %d %s from %s's %s.",
  UNITDIESSELF="You die.", UNITDIESOTHER="%s dies.", UNITDESTROYEDOTHER="%s is destroyed.",
  ABSORB_TRAILER=" (%d absorbed)", BLOCK_TRAILER=" (%d blocked)", RESIST_TRAILER=" (%d resisted)",
  GLANCING_TRAILER=" (glancing)", CRUSHING_TRAILER=" (crushing)", VULNERABLE_TRAILER=" (%d vulnerability bonus)",
}
P.EN = EN

-- Spec rows: {GLOBAL, kind, "capture field order", fixed fields...}
-- fields: s source, sp spell, t target, a amount, sc school, pt power type, k miss kind
-- fixed: s="me"/t="me" are the player; crit, periodic, harm, gone, k.
local ME = "me"
local SPECS = {
 melee = {
  {"COMBATHITCRITSCHOOLOTHERSELF","dmg","s a sc",t=ME,crit=1,sp="Melee"}, {"COMBATHITSCHOOLOTHERSELF","dmg","s a sc",t=ME,sp="Melee"},
  {"COMBATHITCRITOTHERSELF","dmg","s a",t=ME,crit=1,sp="Melee"}, {"COMBATHITOTHERSELF","dmg","s a",t=ME,sp="Melee"},
  {"COMBATHITCRITSCHOOLSELFOTHER","dmg","t a sc",s=ME,crit=1,sp="Melee"}, {"COMBATHITSCHOOLSELFOTHER","dmg","t a sc",s=ME,sp="Melee"},
  {"COMBATHITCRITSELFOTHER","dmg","t a",s=ME,crit=1,sp="Melee"}, {"COMBATHITSELFOTHER","dmg","t a",s=ME,sp="Melee"},
  {"COMBATHITCRITSCHOOLOTHEROTHER","dmg","s t a sc",crit=1,sp="Melee"}, {"COMBATHITSCHOOLOTHEROTHER","dmg","s t a sc",sp="Melee"},
  {"COMBATHITCRITOTHEROTHER","dmg","s t a",crit=1,sp="Melee"}, {"COMBATHITOTHEROTHER","dmg","s t a",sp="Melee"},
 },
 meleemiss = {
  {"MISSEDOTHERSELF","miss","s",t=ME,k="miss",sp="Melee"}, {"MISSEDSELFOTHER","miss","t",s=ME,k="miss",sp="Melee"}, {"MISSEDOTHEROTHER","miss","s t",k="miss",sp="Melee"},
  {"VSDODGEOTHERSELF","miss","s",t=ME,k="dodge",sp="Melee"}, {"VSDODGESELFOTHER","miss","t",s=ME,k="dodge",sp="Melee"}, {"VSDODGEOTHEROTHER","miss","s t",k="dodge",sp="Melee"},
  {"VSPARRYOTHERSELF","miss","s",t=ME,k="parry",sp="Melee"}, {"VSPARRYSELFOTHER","miss","t",s=ME,k="parry",sp="Melee"}, {"VSPARRYOTHEROTHER","miss","s t",k="parry",sp="Melee"},
  {"VSBLOCKOTHERSELF","miss","s",t=ME,k="block",sp="Melee"}, {"VSBLOCKSELFOTHER","miss","t",s=ME,k="block",sp="Melee"}, {"VSBLOCKOTHEROTHER","miss","s t",k="block",sp="Melee"},
  {"VSEVADESELFOTHER","miss","t",s=ME,k="evade",sp="Melee"}, {"VSEVADEOTHEROTHER","miss","s t",k="evade",sp="Melee"},
  {"VSIMMUNEOTHERSELF","miss","s",t=ME,k="immune",sp="Melee"}, {"VSIMMUNESELFOTHER","miss","t",s=ME,k="immune",sp="Melee"}, {"VSIMMUNEOTHEROTHER","miss","s t",k="immune",sp="Melee"},
  {"VSABSORBOTHERSELF","miss","s",t=ME,k="absorb",sp="Melee"}, {"VSABSORBSELFOTHER","miss","t",s=ME,k="absorb",sp="Melee"}, {"VSABSORBOTHEROTHER","miss","s t",k="absorb",sp="Melee"},
 },
 spelldmg = {
  {"SPELLLOGCRITSCHOOLSELFSELF","dmg","sp a sc",s=ME,t=ME,crit=1}, {"SPELLLOGSCHOOLSELFSELF","dmg","sp a sc",s=ME,t=ME},
  {"SPELLLOGCRITSELFSELF","dmg","sp a",s=ME,t=ME,crit=1}, {"SPELLLOGSELFSELF","dmg","sp a",s=ME,t=ME},
  {"SPELLLOGCRITSCHOOLOTHERSELF","dmg","s sp a sc",t=ME,crit=1}, {"SPELLLOGSCHOOLOTHERSELF","dmg","s sp a sc",t=ME},
  {"SPELLLOGCRITOTHERSELF","dmg","s sp a",t=ME,crit=1}, {"SPELLLOGOTHERSELF","dmg","s sp a",t=ME},
  {"SPELLLOGCRITSCHOOLSELFOTHER","dmg","sp t a sc",s=ME,crit=1}, {"SPELLLOGSCHOOLSELFOTHER","dmg","sp t a sc",s=ME},
  {"SPELLLOGCRITSELFOTHER","dmg","sp t a",s=ME,crit=1}, {"SPELLLOGSELFOTHER","dmg","sp t a",s=ME},
  {"SPELLLOGCRITSCHOOLOTHEROTHER","dmg","s sp t a sc",crit=1}, {"SPELLLOGSCHOOLOTHEROTHER","dmg","s sp t a sc"},
  {"SPELLLOGCRITOTHEROTHER","dmg","s sp t a",crit=1}, {"SPELLLOGOTHEROTHER","dmg","s sp t a"},
 },
 spellmiss = {
  {"SPELLMISSOTHERSELF","miss","s sp",t=ME,k="miss"}, {"SPELLMISSSELFOTHER","miss","sp t",s=ME,k="miss"}, {"SPELLMISSOTHEROTHER","miss","s sp t",k="miss"},
  {"SPELLRESISTOTHEROTHER","miss","s sp t",k="resist"}, {"SPELLRESISTSELFOTHER","miss","sp t",s=ME,k="resist"}, {"SPELLRESISTOTHERSELF","miss","s sp",t=ME,k="resist"},
  {"SPELLDODGEDOTHEROTHER","miss","s sp t",k="dodge"}, {"SPELLDODGEDSELFOTHER","miss","sp t",s=ME,k="dodge"}, {"SPELLDODGEDOTHERSELF","miss","s sp",t=ME,k="dodge"},
  {"SPELLPARRIEDOTHEROTHER","miss","s sp t",k="parry"}, {"SPELLPARRIEDSELFOTHER","miss","sp t",s=ME,k="parry"}, {"SPELLPARRIEDOTHERSELF","miss","s sp",t=ME,k="parry"},
  {"SPELLBLOCKEDOTHEROTHER","miss","s sp t",k="block"}, {"SPELLBLOCKEDSELFOTHER","miss","sp t",s=ME,k="block"}, {"SPELLBLOCKEDOTHERSELF","miss","s sp",t=ME,k="block"},
  {"SPELLEVADEDSELFOTHER","miss","sp t",s=ME,k="evade"}, {"SPELLEVADEDOTHEROTHER","miss","s sp t",k="evade"},
  {"SPELLIMMUNEOTHERSELF","miss","s sp",t=ME,k="immune"}, {"SPELLIMMUNESELFOTHER","miss","sp t",s=ME,k="immune"}, {"SPELLIMMUNEOTHEROTHER","miss","s sp t",k="immune"},
  {"SPELLLOGABSORBOTHERSELF","miss","s sp",t=ME,k="absorb"}, {"SPELLLOGABSORBSELFOTHER","miss","sp t",s=ME,k="absorb"}, {"SPELLLOGABSORBOTHEROTHER","miss","s sp t",k="absorb"},
  {"SPELLREFLECTOTHERSELF","miss","s sp",t=ME,k="reflect"}, {"SPELLREFLECTSELFOTHER","miss","sp t",s=ME,k="reflect"}, {"SPELLREFLECTOTHEROTHER","miss","s sp t",k="reflect"},
 },
 periodicdmg = {
  {"PERIODICAURADAMAGESELFSELF","dmg","a sc sp",s=ME,t=ME,periodic=1}, {"PERIODICAURADAMAGEOTHERSELF","dmg","a sc s sp",t=ME,periodic=1},
  {"PERIODICAURADAMAGESELFOTHER","dmg","t a sc sp",s=ME,periodic=1}, {"PERIODICAURADAMAGEOTHEROTHER","dmg","t a sc s sp",periodic=1},
 },
 periodicheal = {
  {"PERIODICAURAHEALSELFSELF","heal","a sp",s=ME,t=ME,periodic=1}, {"PERIODICAURAHEALOTHERSELF","heal","a s sp",t=ME,periodic=1},
  {"PERIODICAURAHEALSELFOTHER","heal","t a sp",s=ME,periodic=1}, {"PERIODICAURAHEALOTHEROTHER","heal","t a s sp",periodic=1},
 },
 heal = {
  {"HEALEDCRITSELFSELF","heal","sp a",s=ME,t=ME,crit=1}, {"HEALEDSELFSELF","heal","sp a",s=ME,t=ME},
  {"HEALEDCRITOTHERSELF","heal","s sp a",t=ME,crit=1}, {"HEALEDOTHERSELF","heal","s sp a",t=ME},
  {"HEALEDCRITSELFOTHER","heal","sp t a",s=ME,crit=1}, {"HEALEDSELFOTHER","heal","sp t a",s=ME},
  {"HEALEDCRITOTHEROTHER","heal","s sp t a",crit=1}, {"HEALEDOTHEROTHER","heal","s sp t a"},
 },
 shield = {
  {"DAMAGESHIELDSELFOTHER","dmg","a sc t",s=ME,sp="Damage Shield"}, {"DAMAGESHIELDOTHERSELF","dmg","s a sc",t=ME,sp="Damage Shield"},
  {"DAMAGESHIELDOTHEROTHER","dmg","s a sc t",sp="Damage Shield"},
 },
 power = {
  {"POWERGAINSELFSELF","power","a pt sp",s=ME,t=ME}, {"POWERGAINOTHERSELF","power","a pt s sp",t=ME},
  {"POWERGAINSELFOTHER","power","t a pt sp",s=ME}, {"POWERGAINOTHEROTHER","power","t a pt s sp"},
 },
 auraadd = {
  {"AURAAPPLICATIONADDEDSELFHELPFUL","aura","sp a",t=ME}, {"AURAAPPLICATIONADDEDSELFHARMFUL","aura","sp a",t=ME,harm=1},
  {"AURAAPPLICATIONADDEDOTHERHELPFUL","aura","t sp a"}, {"AURAAPPLICATIONADDEDOTHERHARMFUL","aura","t sp a",harm=1},
  {"AURAADDEDSELFHELPFUL","aura","sp",t=ME}, {"AURAADDEDSELFHARMFUL","aura","sp",t=ME,harm=1},
  {"AURAADDEDOTHERHELPFUL","aura","t sp"}, {"AURAADDEDOTHERHARMFUL","aura","t sp",harm=1},
 },
 auragone = {
  {"AURAREMOVEDSELF","aura","sp",t=ME,gone=1}, {"AURAREMOVEDOTHER","aura","sp t",gone=1},
  {"AURADISPELSELF","aura","sp",t=ME,gone=1,dispelled=1}, {"AURADISPELOTHER","aura","t sp",gone=1,dispelled=1},
 },
 cast = {
  {"SIMPLECASTSELFSELF","cast","sp",s=ME,t=ME}, {"SIMPLECASTOTHERSELF","cast","s sp",t=ME}, {"SIMPLECASTSELFOTHER","cast","sp t",s=ME}, {"SIMPLECASTOTHEROTHER","cast","s sp t"},
  {"SIMPLEPERFORMOTHERSELF","cast","s sp",t=ME}, {"SIMPLEPERFORMSELFOTHER","cast","sp t",s=ME}, {"SIMPLEPERFORMOTHEROTHER","cast","s sp t"},
  {"SPELLCASTGOSELF","cast","sp",s=ME}, {"SPELLPERFORMGOSELF","cast","sp",s=ME}, {"SPELLCASTGOOTHER","cast","s sp"}, {"SPELLPERFORMGOOTHER","cast","s sp"},
 },
 dispelfail = {
  {"DISPELFAILEDSELFSELF","dispelfail","sp",s=ME,t=ME}, {"DISPELFAILEDSELFOTHER","dispelfail","t sp",s=ME},
  {"DISPELFAILEDOTHERSELF","dispelfail","s sp",t=ME}, {"DISPELFAILEDOTHEROTHER","dispelfail","s t sp"},
 },
 interrupt = {
  {"SPELLINTERRUPTSELFOTHER","interrupt","t sp",s=ME}, {"SPELLINTERRUPTOTHERSELF","interrupt","s sp",t=ME}, {"SPELLINTERRUPTOTHEROTHER","interrupt","s t sp"},
 },
 death = {
  {"UNITDIESSELF","death","",t=ME}, {"UNITDIESOTHER","death","t"}, {"UNITDESTROYEDOTHER","death","t"},
 },
}

local function text(name)
  local g = getglobal and getglobal(name)
  if type(g) == "string" and find(g, "%%") then return g end
  return EN[name]
end

local function compile(fmt, anchorEnd)
  local pat = gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  pat = gsub(pat, "%%s", "(.-)")
  pat = gsub(pat, "%%d", "(%%d+)")
  pat = "^"..pat
  if anchorEnd then pat = pat.."$" end
  return pat
end

local compiled = {}  -- group name -> array of entries
P.count = 0
local FIELDS = {"s","sp","t","a","sc","pt"}

local function build()
  for group, rows in pairs(SPECS) do
    local list = {}
    for i = 1, getn(rows) do
      local row = rows[i]
      local fmt = text(row[1])
      if fmt then
        local map = {}
        local pos = 1
        while true do
          local a, b = find(row[3], "%S+", pos)
          if not a then break end
          table.insert(map, string.sub(row[3], a, b)); pos = b + 1
        end
        local fixed = nil
        for k, v in pairs(row) do
          if type(k) == "string" then fixed = fixed or {}; fixed[k] = v end
        end
        -- Lines whose last token is a number may carry trailers after the period, so never anchor those.
        table.insert(list, {pat = compile(fmt, false), kind = row[2], map = map, fixed = fixed, name = row[1]})
        P.count = P.count + 1
      end
    end
    compiled[group] = list
  end
end

-- Trailers after damage lines: " (12 absorbed)" etc.
local trailers = {}
local function buildTrailers()
  local function add(global, field)
    local fmt = text(global); if not fmt then return end
    local pat = gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pat = gsub(pat, "%%d", "(%%d+)")
    table.insert(trailers, {pat = pat, field = field, flag = not find(fmt, "%%d")})
  end
  add("ABSORB_TRAILER", "pabsorb"); add("BLOCK_TRAILER", "pblock"); add("RESIST_TRAILER", "presist")
  add("GLANCING_TRAILER", "glance"); add("CRUSHING_TRAILER", "crush"); add("VULNERABLE_TRAILER", "vuln")
end

-- Event -> ordered group lists. "for" lines (hits/heals) and the rest are separated
-- by one plain find so a miss never walks the damage patterns.
local eventGroups = {}
local function groups(names)
  local list = {}
  for i = 1, getn(names) do
    local g = compiled[names[i]]
    if g then for j = 1, getn(g) do table.insert(list, g[j]) end end
  end
  return list
end

P.handles = {}
local function register(frame, event, forList, otherList)
  eventGroups[event] = {forList, otherList}
  P.handles[event] = true
  if frame then frame:RegisterEvent(event) end
end

local function registerAll(frame)
  local hits = groups({"melee"})
  local misses = groups({"meleemiss"})
  local spellFor = groups({"spelldmg", "heal", "melee"})
  local spellOther = groups({"spellmiss", "cast", "interrupt", "dispelfail", "auraadd", "power", "periodicdmg", "periodicheal", "death"})
  local buffFor = groups({"heal", "spelldmg"})
  local buffOther = groups({"power", "auraadd", "cast", "dispelfail", "periodicheal", "interrupt"})
  local periodicDmg = groups({"periodicdmg", "auraadd", "power"})
  local periodicDmgFor = groups({"spelldmg"})
  local periodicBuff = groups({"periodicheal", "power", "auraadd"})
  local periodicBuffFor = groups({"heal"})
  local gone = groups({"auragone"})
  local death = groups({"death"})
  for _, who in ipairs({"SELF", "PARTY", "PET", "FRIENDLYPLAYER", "HOSTILEPLAYER", "CREATURE_VS_SELF", "CREATURE_VS_PARTY", "CREATURE_VS_CREATURE"}) do
    register(frame, "CHAT_MSG_COMBAT_"..who.."_HITS", hits, misses)
    register(frame, "CHAT_MSG_COMBAT_"..who.."_MISSES", hits, misses)
    register(frame, "CHAT_MSG_SPELL_"..who.."_DAMAGE", spellFor, spellOther)
    register(frame, "CHAT_MSG_SPELL_"..who.."_BUFF", buffFor, buffOther)
  end
  for _, who in ipairs({"SELF", "PARTY", "FRIENDLYPLAYER", "HOSTILEPLAYER", "CREATURE"}) do
    register(frame, "CHAT_MSG_SPELL_PERIODIC_"..who.."_DAMAGE", periodicDmgFor, periodicDmg)
    register(frame, "CHAT_MSG_SPELL_PERIODIC_"..who.."_BUFFS", periodicBuffFor, periodicBuff)
  end
  local shields = groups({"shield"})
  register(frame, "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", shields, shields)
  register(frame, "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS", shields, shields)
  register(frame, "CHAT_MSG_SPELL_AURA_GONE_SELF", gone, gone)
  register(frame, "CHAT_MSG_SPELL_AURA_GONE_PARTY", gone, gone)
  register(frame, "CHAT_MSG_SPELL_AURA_GONE_OTHER", gone, gone)
  register(frame, "CHAT_MSG_SPELL_BREAK_AURA", gone, gone)
  register(frame, "CHAT_MSG_COMBAT_HOSTILE_DEATH", death, death)
  register(frame, "CHAT_MSG_COMBAT_FRIENDLY_DEATH", death, death)
end

-- Reused record handed to the data layer. Never retained by callers.
local rec = {}
P.rec = rec
local FOR = " for "

local function clear()
  rec.s = nil; rec.sp = nil; rec.t = nil; rec.a = nil; rec.sc = nil; rec.pt = nil; rec.k = nil
  rec.crit = nil; rec.periodic = nil; rec.harm = nil; rec.gone = nil; rec.dispelled = nil
  rec.pabsorb = nil; rec.pblock = nil; rec.presist = nil; rec.glance = nil; rec.crush = nil; rec.vuln = nil
end

local function tryList(list, line)
  for i = 1, getn(list) do
    local e = list[i]
    local _, stop, c1, c2, c3, c4, c5 = find(line, e.pat)
    if stop then
      clear()
      local m = e.map
      if m[1] then rec[m[1]] = c1 end
      if m[2] then rec[m[2]] = c2 end
      if m[3] then rec[m[3]] = c3 end
      if m[4] then rec[m[4]] = c4 end
      if m[5] then rec[m[5]] = c5 end
      local f = e.fixed
      if f then for k, v in pairs(f) do rec[k] = v end end
      if rec.s == ME then rec.s = Z.playerName end
      if rec.t == ME then rec.t = Z.playerName end
      if rec.a then rec.a = tonumber(rec.a) end
      if e.kind == "dmg" and stop < string.len(line) then
        for j = 1, getn(trailers) do
          local tr = trailers[j]
          local _, _, n = find(line, tr.pat, stop, false)
          if n or (tr.flag and find(line, tr.pat, stop)) then rec[tr.field] = tr.flag and 1 or tonumber(n) end
        end
      end
      return e.kind, e
    end
  end
end

-- Parse one line for a given event. Returns kind (or nil) and fills P.rec.
function P.Parse(event, line)
  local g = eventGroups[event]
  if not g or not line then return nil end
  if find(line, FOR, 1, true) then return tryList(g[1], line) end
  return tryList(g[2], line)
end

function P.OnEvent(event, line)
  local kind = P.Parse(event, line)
  if kind then Z.Data.Handle(kind, rec) end
end

function P.Init(frame)
  build()
  buildTrailers()
  registerAll(frame)
end

-- Test hook: compile without a frame.
function P.InitForTests() build(); buildTrailers(); registerAll(nil) end
