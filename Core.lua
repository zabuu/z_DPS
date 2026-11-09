-- zDPS: compact damage meter for the 1.12 client.
-- Core: namespace, saved settings, roster, combat segments, slash commands.
zDPS = zDPS or {}
local Z = zDPS
Z.version = "0.1.0"

local find, getn = string.find, table.getn
local GetTime = GetTime

Z.defaults = {
  locked = false, showTitle = true, classColors = true, classIcons = true,
  mergePets = true, shortNumbers = true, showPercent = true, showRank = false,
  rowHeight = 13, fontSize = 10, barAlpha = .85, barTexture = "flat",
  metric = "dps", mode = "current", historySize = 5, dpsTime = "fight",
  resetTotal = "never",   -- never | group | instance | combat
  fightOpacity = 1, idleOpacity = 1,
  width = 180, height = 118, point = "CENTER", x = 260, y = -120,
  threatRows = 8, reportRows = 5,
  outline = "none",        -- none | thin | thick: outline around all text
  showPerSecond = true,    -- Damage and Healing rows also show DPS / HPS in parentheses
  show = "always",         -- always | combat | linger (in combat, then 5s after)
  bgColor = { .04, .05, .07, .7 }, titleColor = { .08, .1, .13, 1 }, borderColor = { .18, .22, .28, 1 },
  textColor = { .92, .94, .97 }, barColor = { .2, .78, .68 },   -- barColor: bars when class colours are off
}

-- Settings a single window can have its own value for (zDPSDB.windows[i].over[key]).
-- Everything else is shared by all windows.
Z.WINDOW_KEYS = { "show", "fightOpacity", "idleOpacity", "showTitle", "rowHeight", "fontSize", "outline",
  "classColors", "classIcons", "showPercent", "showRank", "showPerSecond", "barAlpha",
  "bgColor", "titleColor", "borderColor", "textColor", "barColor" }
Z.isWindowKey = {}
for _, k in ipairs(Z.WINDOW_KEYS) do Z.isWindowKey[k] = true end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = x end
  return t
end
Z.Copy = copy

-- Font flags for the text outline setting.
local OUTLINE = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
function Z.FontFlags(outline) return OUTLINE[outline or (Z.db and Z.db.outline) or "none"] or "" end

function Z.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff7dff33zDPS|r "..tostring(msg)) end

function Z.LoadSettings()
  if type(zDPSDB) ~= "table" then zDPSDB = {} end
  -- earlier versions: one hide-out-of-combat switch and a background opacity
  if zDPSDB.show == nil and zDPSDB.hideOutOfCombat then zDPSDB.show = "combat" end
  if zDPSDB.bgColor == nil and zDPSDB.backdropAlpha then
    local d = Z.defaults.bgColor
    zDPSDB.bgColor = { d[1], d[2], d[3], zDPSDB.backdropAlpha }
  end
  for k, v in pairs(Z.defaults) do if zDPSDB[k] == nil then zDPSDB[k] = copy(v) end end
  Z.db = zDPSDB
end

-- Roster -----------------------------------------------------------------
-- roster[name] = {class=, owner=} ; pets carry owner. Rebuilt on group changes only.
Z.roster = {}
Z.playerName = nil
Z.singleShaman = nil
local rosterPool = {}
local lastRosterRefresh = 0

local function addMember(unit, owner)
  local name = UnitName(unit)
  if not name or name == UNKNOWNOBJECT then return end
  local rec = Z.roster[name] or table.remove(rosterPool) or {}
  if owner then rec.class = "PET"; rec.owner = owner
  else local _, class = UnitClass(unit); rec.class = class or "UNKNOWN"; rec.owner = nil end
  Z.roster[name] = rec
  return name, rec
end

function Z.RefreshRoster()
  lastRosterRefresh = GetTime()
  for name, rec in pairs(Z.roster) do Z.roster[name] = nil; table.insert(rosterPool, rec) end
  Z.playerName = UnitName("player")
  addMember("player")
  addMember("pet", Z.playerName)
  local raid = GetNumRaidMembers()
  if raid > 0 then
    for i = 1, raid do
      local name = addMember("raid"..i)
      if name and UnitExists("raidpet"..i) then addMember("raidpet"..i, name) end
    end
  else
    for i = 1, GetNumPartyMembers() do
      local name = addMember("party"..i)
      if name and UnitExists("partypet"..i) then addMember("partypet"..i, name) end
    end
  end
  local shamans, single = 0, nil
  for name, rec in pairs(Z.roster) do
    if rec.class == "SHAMAN" then shamans = shamans + 1; single = name end
  end
  Z.singleShaman = (shamans == 1) and single or nil
  Z.groupSize = raid > 0 and raid or GetNumPartyMembers()
  if Z.Data then Z.Data.OnRoster() end
end

-- Returns owner name for a tracked source, or nil for a non-group unit.
-- Second value is the pet name when the source is a pet.
function Z.ResolveSource(name)
  local rec = Z.roster[name]
  if not rec then
    -- A pet summoned since the last roster event shows up here first; re-read the
    -- group at most every 5s so a stream of mob names costs nothing.
    local now = GetTime()
    if now - lastRosterRefresh > 5 then Z.RefreshRoster(); rec = Z.roster[name] end
  end
  if rec then
    if rec.owner then
      if Z.db.mergePets then return rec.owner, name end
      return name, nil
    end
    return name, nil
  end
  if Z.singleShaman and find(name, "Totem", 1, true) then
    if Z.db.mergePets then return Z.singleShaman, name end
    return name, nil
  end
  return nil
end

function Z.ClassOf(name)
  local rec = Z.roster[name]
  if rec then return rec.class end
  if find(name, "Totem", 1, true) then return "PET" end
  return "UNKNOWN"
end

-- Combat segments -----------------------------------------------------------
-- A fight opens when the player or any group member enters combat, or when a
-- group member deals/receives damage. It closes once nobody in the group is in
-- combat for two consecutive 1s checks.
Z.inFight = false
local ticker = CreateFrame("Frame")
ticker:Hide()
local tickAt, quietTicks = 0, 0

local function groupInCombat()
  if UnitAffectingCombat("player") then return true end
  local raid = GetNumRaidMembers()
  if raid > 0 then
    for i = 1, raid do if UnitAffectingCombat("raid"..i) then return true end end
  else
    for i = 1, GetNumPartyMembers() do if UnitAffectingCombat("party"..i) then return true end end
  end
  return false
end

function Z.StartFight()
  if Z.inFight then return end
  Z.inFight = true
  quietTicks = 0
  Z.Data.StartFight()
  if Z.db.resetTotal == "combat" then Z.Data.ResetTotal() end
  tickAt = GetTime() + 1
  ticker:Show()
  if Z.UI then Z.UI.OnCombat(true) end
end

function Z.EndFight()
  if not Z.inFight then return end
  Z.inFight = false
  Z.Data.EndFight()
  ticker:Hide()
  if Z.UI then Z.UI.OnCombat(false) end
end

ticker:SetScript("OnUpdate", function()
  local now = GetTime()
  if now < tickAt then return end
  tickAt = now + 1
  if groupInCombat() then quietTicks = 0
  else
    quietTicks = quietTicks + 1
    if quietTicks >= 2 then Z.EndFight() end
  end
end)

-- Events --------------------------------------------------------------------
local core = CreateFrame("Frame", "zDPSCore")
Z.frame = core
local lastInstance = nil

local function onEvent(event, a1)
  if event == "PLAYER_REGEN_DISABLED" then
    Z.StartFight()
  elseif event == "UNIT_HEALTH" then
    Z.Data.OnUnitHealth(a1)
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "UNIT_PET" then
    local before = Z.groupSize or 0
    Z.RefreshRoster()
    if Z.db.resetTotal == "group" and before == 0 and (Z.groupSize or 0) > 0 then Z.Data.ResetTotal() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    Z.RefreshRoster()
    local inInstance = IsInInstance and IsInInstance() or nil
    local zone = GetRealZoneText()
    if Z.db.resetTotal == "instance" and zone ~= lastInstance and (inInstance or inInstance == nil) then
      if lastInstance ~= nil then Z.Data.ResetTotal() end
    end
    lastInstance = zone
    if UnitAffectingCombat("player") then Z.StartFight() end
  elseif event == "VARIABLES_LOADED" then
    Z.LoadSettings()
    Z.RefreshRoster()
    Z.Parser.Init(core)
    Z.Threat.Init(core)
    Z.UI.Init()
    Z.Print("loaded. /zdps for commands.")
  end
end

core:SetScript("OnEvent", function()
  if Z.Parser.handles[event] then Z.Parser.OnEvent(event, arg1) return end
  if event == "CHAT_MSG_ADDON" then Z.Threat.OnAddon(arg1, arg2) return end
  onEvent(event, arg1)
end)
core:RegisterEvent("VARIABLES_LOADED")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("PLAYER_REGEN_DISABLED")
core:RegisterEvent("PARTY_MEMBERS_CHANGED")
core:RegisterEvent("RAID_ROSTER_UPDATE")
core:RegisterEvent("UNIT_PET")
core:RegisterEvent("UNIT_HEALTH")

-- Slash -----------------------------------------------------------------------
SLASH_ZDPS1 = "/zdps"
SlashCmdList["ZDPS"] = function(msg)
  msg = string.lower(msg or "")
  local _, _, cmd, rest = find(msg, "^(%S*)%s*(.-)$")
  if cmd == "reset" then Z.Data.ResetAll(); Z.UI.Refresh()
  elseif cmd == "lock" then Z.db.locked = not Z.db.locked; Z.UI.ApplySettings(); Z.Print(Z.db.locked and "locked" or "unlocked")
  elseif cmd == "show" then Z.UI.Show()
  elseif cmd == "hide" then Z.UI.Hide()
  elseif cmd == "toggle" or cmd == "" then Z.UI.Toggle()
  elseif cmd == "config" or cmd == "options" then Z.Config.Toggle()
  elseif cmd == "mode" then Z.UI.SetMode(rest)
  elseif cmd == "metric" then Z.UI.SetMetric(rest)
  elseif cmd == "report" then Z.UI.Report(rest ~= "" and rest or nil)
  elseif cmd == "debug" then
    Z.debug = not Z.debug; Z.Print("debug "..(Z.debug and "on: pet lines are echoed" or "off"))
  elseif cmd == "roster" then
    for name, rec in pairs(Z.roster) do Z.Print(name.."  "..rec.class..(rec.owner and ("  owner: "..rec.owner) or "")) end
  elseif cmd == "mem" then
    local ok = pcall(UpdateAddOnMemoryUsage)
    local kb = ok and GetAddOnMemoryUsage and GetAddOnMemoryUsage("z_DPS") or 0
    Z.Print(string.format("%.0f KB in use, %d tracked names, %d patterns.", kb, Z.Data.CountPlayers(), Z.Parser.count))
  else
    Z.Print("commands: toggle, show, hide, lock, reset, config, mode <current|total>, metric <dps|...>, report [party|raid|say|<name>], roster, debug, mem")
  end
end
