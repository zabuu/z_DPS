-- Minimal 1.12 widget/API stub for headless tests.
STUB = { time = 100, frames = {}, chat = {}, addon = {}, combat = { player = false }, units = {} }
function GetTime() return STUB.time end
function getglobal(n) return _G[n] end
function GetNumRaidMembers() return STUB.raid or 0 end
function GetNumPartyMembers() return STUB.party or 0 end
function UnitName(u) local r = STUB.units[u]; return r and r.name end
function UnitClass(u) local r = STUB.units[u]; return r and r.class, r and r.class end
function UnitExists(u) return STUB.units[u] ~= nil end
function UnitHealth(u) local r = STUB.units[u]; return r and r.hp or 0 end
function UnitHealthMax(u) local r = STUB.units[u]; return r and r.max or 0 end
function UnitAffectingCombat(u) local r = STUB.units[u]; return r and r.combat or false end
function UnitIsPlayer(u) return false end
function IsAddOnLoaded() return false end
function IsShiftKeyDown() return false end
function GetRealZoneText() return STUB.zone or "Elwynn" end
function IsInInstance() return STUB.instance end
function SendChatMessage(msg, channel, lang, who) table.insert(STUB.chat, { msg = msg, channel = channel, who = who }) end
function SendAddonMessage(prefix, msg, channel) table.insert(STUB.addon, { prefix = prefix, msg = msg, channel = channel }) end
function GetCursorPosition() return 0, 0 end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage() return 100 end
UNKNOWNOBJECT = "Unknown"
RAID_CLASS_COLORS = { MAGE = { r = .4, g = .8, b = .94 }, WARRIOR = { r = .78, g = .61, b = .43 }, SHAMAN = { r = 0, g = .44, b = .87 }, PRIEST = { r = 1, g = 1, b = 1 } }
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(STUB.chat, { msg = m, channel = "LOCAL" }) end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddDoubleLine = function() end, Show = function() end, Hide = function() end }

local widget = {}
widget.__index = widget
local function noop() end
for _, m in ipairs({ "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetFrameStrata", "EnableMouse", "EnableMouseWheel",
  "SetClampedToScreen", "RegisterForDrag", "RegisterForClicks", "SetMovable", "SetResizable", "SetMinResize", "StartMoving",
  "StopMovingOrSizing", "StartSizing", "SetTexture", "SetVertexColor", "SetFont", "SetShadowColor", "SetShadowOffset", "SetTextColor",
  "SetJustifyH", "SetOrientation", "SetThumbTexture", "SetMinMaxValues", "SetValueStep", "SetCheckedTexture", "SetFontObject", "SetTextInsets", "SetAutoFocus" }) do
  widget[m] = noop
end
function widget:SetPoint(point, rel, relPoint, x, y) self.points = self.points or {}; table.insert(self.points, { point, rel, relPoint, x, y }) end
function widget:ClearAllPoints() self.points = {} end
function widget:SetAllPoints() end
function widget:SetWidth(w) self.width = w end
function widget:SetHeight(h) self.height = h end
function widget:GetWidth() return self.width or 0 end
function widget:GetHeight() return self.height or 0 end
function widget:GetLeft() return 10 end
function widget:GetTop() return 500 end
function widget:GetRight() return 10 + (self.width or 0) end
function widget:GetBottom() return 500 - (self.height or 0) end
function widget:GetEffectiveScale() return 1 end
function widget:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then this = self; self.scripts.OnShow() end end
function widget:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then this = self; self.scripts.OnHide() end end
function widget:IsShown() return self.shown end
function widget:IsVisible() return self.shown end
function widget:SetAlpha(a) self.alpha = a end
function widget:GetAlpha() return self.alpha or 1 end
function widget:SetScript(name, fn) self.scripts[name] = fn end
function widget:GetScript(name) return self.scripts[name] end
function widget:RegisterEvent(e) self.events[e] = true; STUB.frames[e] = STUB.frames[e] or {}; table.insert(STUB.frames[e], self) end
function widget:UnregisterEvent(e) self.events[e] = nil end
function widget:SetText(t) self.text_ = t end
function widget:GetText() return self.text_ end
function widget:GetStringWidth() return string.len(self.text_ or "") * 5 end
function widget:SetChecked(v) self.checked = v end
function widget:GetChecked() return self.checked end
function widget:SetValue(v) self.value_ = v end
function widget:GetValue() return self.value_ or 0 end
function widget:CreateTexture() return setmetatable({ scripts = {}, events = {} }, widget) end
function widget:GetCheckedTexture() return self:CreateTexture() end
function widget:GetThumbTexture() return self:CreateTexture() end
function widget:CreateFontString() return setmetatable({ scripts = {}, events = {} }, widget) end
function CreateFrame(kind, name, parent)
  local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, shown = true }, widget)
  if name then _G[name] = f end
  table.insert(STUB.frames, f)
  return f
end
UIParent = CreateFrame("Frame", "UIParent")

-- Deliver an event to every frame registered for it, 1.12 style (globals event/arg1..).
function STUB.fire(ev, a1, a2, a3, a4)
  for _, f in ipairs(STUB.frames[ev] or {}) do
    if f.scripts.OnEvent then this = f; event = ev; arg1 = a1; arg2 = a2; arg3 = a3; arg4 = a4; f.scripts.OnEvent() end
  end
end
function STUB.tick(dt)
  STUB.time = STUB.time + (dt or 1)
  for _, f in ipairs(STUB.frames) do
    if f.shown and f.scripts.OnUpdate then this = f; arg1 = dt or 1; f.scripts.OnUpdate() end
  end
end
function STUB.load(root)
  for _, name in ipairs({ "Core.lua", "Lists.lua", "Parser.lua", "Data.lua", "Threat.lua", "UI.lua", "Config.lua" }) do
    local chunk = assert(loadfile(root.."/"..name)); chunk()
  end
end
