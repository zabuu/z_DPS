-- zDPS: live threat from the Turtle/OctoWoW server threat API (the same
-- CHAT_MSG_ADDON protocol TWThreat uses). When TWThreat is loaded its queries
-- are reused; otherwise zDPS asks once per second while the Threat view is open,
-- in a group, and both the player and target are in combat.
local Z = zDPS
local T = {}
Z.Threat = T

local find, sub, getn, tonumber = string.find, string.sub, table.getn, tonumber
local QUERY = "TWT_UDTSv4"
local TAG = "TWTv4="

T.rows = {}      -- {name, threat, perc, tank, tps}
T.rows.n = 0
T.lastPacket = 0
T.target = nil
local history = {} -- name -> {t1, v1, t2, v2}
local query = CreateFrame("Frame")
query:Hide()
local nextQuery = 0

local function channel() return GetNumRaidMembers() > 0 and "RAID" or "PARTY" end

local function wantQueries()
  if not Z.UI or not Z.UI.IsThreatVisible() then return false end
  if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return false end
  if IsAddOnLoaded and IsAddOnLoaded("TWThreat") then return false end
  return true
end

query:SetScript("OnUpdate", function()
  local now = GetTime()
  if now < nextQuery then return end
  nextQuery = now + 1
  if not wantQueries() then query:Hide(); return end
  if UnitAffectingCombat("player") and UnitExists("target") and UnitAffectingCombat("target") and not UnitIsPlayer("target") then
    SendAddonMessage(QUERY, "limit="..(Z.db.threatRows or 8), channel())
  end
end)

function T.Start() nextQuery = 0; query:Show() end
function T.Stop() query:Hide() end

local function split(line, sep, out)
  local n, pos = 0, 1
  while true do
    local a = find(line, sep, pos, true)
    n = n + 1
    if a then out[n] = sub(line, pos, a - 1); pos = a + 1 else out[n] = sub(line, pos); break end
  end
  return n
end

local players, fields = {}, {}

local function tps(name, threat, now)
  local h = history[name]
  if not h then h = {}; history[name] = h end
  local rate = 0
  if h.t1 and now > h.t1 then rate = (threat - h.v1) / (now - h.t1) end
  if not h.t1 or now - h.t1 >= 3 then h.t1 = h.t2 or now; h.v1 = h.v2 or threat end
  h.t2 = now; h.v2 = threat
  return rate > 0 and rate or 0
end

function T.HandlePacket(msg)
  local a, b = find(msg, TAG, 1, true)
  if not a then return end
  local hash = find(msg, "#", b, true)
  local body = sub(msg, b + 1, hash and hash - 1 or nil)
  local now = GetTime()
  local count = split(body, ";", players)
  local n = 0
  for i = 1, count do
    local entry = players[i]
    if entry ~= "" then
      local fn = split(entry, ":", fields)
      if fn >= 4 then
        n = n + 1
        local r = T.rows[n]
        if not r then r = {}; T.rows[n] = r end
        r.name = fields[1]; r.tank = fields[2] == "1"
        r.value = tonumber(fields[3]) or 0; r.perc = tonumber(fields[4]) or 0
        r.tps = tps(r.name, r.value, now)
        r.class = Z.ClassOf(r.name); r.key = r.name; r.kind = "threat"
      end
    end
  end
  for i = n + 1, getn(T.rows) do T.rows[i].name = nil; T.rows[i].value = nil end
  T.rows.n = n
  T.lastPacket = now
  T.target = UnitName("target")
  if Z.UI then Z.UI.Dirty() end
end

function T.OnAddon(prefix, msg)
  if msg and find(msg, TAG, 1, true) then T.HandlePacket(msg) end
end

function T.Init(frame)
  frame:RegisterEvent("CHAT_MSG_ADDON")
end
