-- zDPS: compact damage meter for the 1.12 client.
-- Core: namespace, saved settings, roster, combat segments, slash commands.
zDPS = zDPS or {}
local Z = zDPS
Z.version = "0.1.0"

local find, getn = string.find, table.getn
local GetTime = GetTime

Z.defaults = {
  locked = false, hideOutOfCombat = false, showTitle = true, classColors = true, classIcons = true,
  mergePets = true, shortNumbers = true, showPercent = true, showRank = false,
  rowHeight = 13, fontSize = 10, barAlpha = .85, backdropAlpha = .7, barTexture = "flat",
  metric = "dps", mode = "current", historySize = 5, dpsTime = "fight",
  resetTotal = "never",   -- never | group | instance | combat
  fightOpacity = 1, idleOpacity = 1,
  width = 180, height = 118, point = "CENTER", x = 260, y = -120,
  threatRows = 8, reportRows = 5,
}

function Z.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff7dff33zDPS|r "..tostring(msg)) end

function Z.LoadSettings()
  if type(zDPSDB) ~= "table" then zDPSDB = {} end
  for k, v in pairs(Z.defaults) do if zDPSDB[k] == nil then zDPSDB[k] = v end end
  Z.db = zDPSDB
end

-- Roster -----------------------------------------------------------------
-- roster[name] = {class=, owner=} ; pets carry owner. Rebuilt on group changes only.
Z.roster = {}
Z.playerName = nil
Z.singleShaman = nil
local rosterPool = {}

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
  elseif cmd == "mem" then
    local ok = pcall(UpdateAddOnMemoryUsage)
    local kb = ok and GetAddOnMemoryUsage and GetAddOnMemoryUsage("z_DPS") or 0
    Z.Print(string.format("%.0f KB in use, %d tracked names, %d patterns.", kb, Z.Data.CountPlayers(), Z.Parser.count))
  else
    Z.Print("commands: toggle, show, hide, lock, reset, config, mode <current|total>, metric <dps|...>, report [party|raid|say|<name>], mem")
  end
end
