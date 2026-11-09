-- zDPS: settings window. Built on first open; plain checkboxes, sliders and
-- cycle buttons on one compact surface.
local Z = zDPS
local C = {}
Z.Config = C

local getn, format, floor = table.getn, string.format, math.floor
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"
local frame
local widgets = {}
local ROW = 16
local COL = 150

local function font(fs, size, muted)
  fs:SetFont(FONT, size or 10, "")
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, .9); fs:SetShadowOffset(1, -1) end
  local c = muted and Z.UI.colors.muted or Z.UI.colors.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function apply()
  Z.UI.ApplySettings()
end

local function check(parent, label, key, x, y, onChange)
  local b = CreateFrame("CheckButton", nil, parent)
  b:SetWidth(11); b:SetHeight(11)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(.09, .11, .14, 1); b:SetBackdropBorderColor(.3, .36, .44, 1)
  b:SetCheckedTexture(WHITE)
  local tick = b:GetCheckedTexture()
  if tick then
    tick:ClearAllPoints(); tick:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); tick:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    local a = Z.UI.colors.accent; tick:SetVertexColor(a[1], a[2], a[3], 1)
  end
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetPoint("LEFT", b, "RIGHT", 4, 0); font(b.text); b.text:SetText(label)
  b.hit = CreateFrame("Button", nil, b); b.hit:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.hit:SetWidth(COL - 4); b.hit:SetHeight(ROW - 3)
  b.hit:SetScript("OnClick", function() b:SetChecked(not b:GetChecked()); Z.db[key] = b:GetChecked() and true or false; if onChange then onChange() else apply() end end)
  b.Refresh = function(self) self:SetChecked(Z.db[key]) end
  table.insert(widgets, b)
  return b
end

local function slider(parent, label, key, lo, hi, step, x, y, width)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetWidth(width or 110); s:SetHeight(8)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 12)
  s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  s:SetBackdropColor(.09, .11, .14, 1); s:SetBackdropBorderColor(.3, .36, .44, 1)
  s:SetThumbTexture(WHITE)
  local thumb = s:GetThumbTexture()
  if thumb then thumb:SetWidth(6); thumb:SetHeight(10); local a = Z.UI.colors.accent; thumb:SetVertexColor(a[1], a[2], a[3], 1) end
  s:SetMinMaxValues(lo, hi); s:SetValueStep(step)
  s.text = s:CreateFontString(nil, "OVERLAY"); s.text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3); font(s.text)
  s.value = s:CreateFontString(nil, "OVERLAY"); s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3); font(s.value, 10, true)
  s.text:SetText(label)
  s.updating = false
  s:SetScript("OnValueChanged", function()
    if this.updating then return end
    local v = this:GetValue()
    v = floor(v / step + .5) * step
    if Z.db[key] ~= v then Z.db[key] = v; this.value:SetText(step < 1 and format("%.2f", v) or format("%d", v)); apply() end
  end)
  s.Refresh = function(self)
    self.updating = true; self:SetValue(Z.db[key]); self.updating = false
    self.value:SetText(step < 1 and format("%.2f", Z.db[key]) or format("%d", Z.db[key]))
  end
  table.insert(widgets, s)
  return s
end

local function cycle(parent, label, key, values, x, y, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(COL - 8); b:SetHeight(ROW - 3)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b:SetBackdropColor(.09, .11, .14, 1); b:SetBackdropBorderColor(.3, .36, .44, 1)
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetPoint("LEFT", b, "LEFT", 4, 0); font(b.text, 10, true); b.text:SetText(label)
  b.value = b:CreateFontString(nil, "OVERLAY"); b.value:SetPoint("RIGHT", b, "RIGHT", -4, 0); font(b.value)
  b.Refresh = function(self)
    for i = 1, getn(values) do if values[i][1] == Z.db[key] then self.value:SetText(values[i][2]); return end end
    self.value:SetText(tostring(Z.db[key]))
  end
  b:SetScript("OnClick", function()
    local idx = 1
    for i = 1, getn(values) do if values[i][1] == Z.db[key] then idx = i end end
    idx = idx + 1; if idx > getn(values) then idx = 1 end
    Z.db[key] = values[idx][1]; b:Refresh(); if onChange then onChange() else apply() end
  end)
  table.insert(widgets, b)
  return b
end

local function heading(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY"); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); font(fs, 10, true)
  fs:SetText(text)
end

local function build()
  frame = CreateFrame("Frame", "zDPSConfig", UIParent)
  frame:SetWidth(COL * 2 + 16); frame:SetHeight(238)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  local bg, bd = Z.UI.colors.bg, Z.UI.colors.border
  frame:SetBackdropColor(bg[1], bg[2], bg[3], .97); frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
  frame:SetClampedToScreen(true)
  table.insert(UISpecialFrames, "zDPSConfig")

  local titleText = frame:CreateFontString(nil, "OVERLAY"); titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7); font(titleText, 11)
  titleText:SetText("zDPS settings  |cff6b7682v"..Z.version.."|r")
  local close = CreateFrame("Button", nil, frame); close:SetWidth(12); close:SetHeight(12); close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  close.text = close:CreateFontString(nil, "OVERLAY"); close.text:SetPoint("CENTER", close, "CENTER", 0, 0); font(close.text, 10, true); close.text:SetText("x")
  close:SetScript("OnClick", function() frame:Hide() end)

  local x1, x2, y = 8, COL + 8, -26
  heading(frame, "Window", x1, y); heading(frame, "Tracking", x2, y); y = y - ROW
  check(frame, "Locked", "locked", x1, y)
  check(frame, "Merge pets into owner", "mergePets", x2, y, function() Z.Data.ResetAll(); apply() end); y = y - ROW
  check(frame, "Show title bar", "showTitle", x1, y)
  check(frame, "Class colours", "classColors", x2, y); y = y - ROW
  check(frame, "Hide out of combat", "hideOutOfCombat", x1, y)
  check(frame, "Class icons", "classIcons", x2, y); y = y - ROW
  check(frame, "Short numbers (1.2k)", "shortNumbers", x1, y)
  check(frame, "Show percent", "showPercent", x2, y); y = y - ROW
  check(frame, "Rank numbers", "showRank", x2, y); y = y - ROW - 2
  cycle(frame, "DPS time", "dpsTime", { { "fight", "Fight" }, { "active", "Active" } }, x1, y)
  cycle(frame, "Reset total", "resetTotal", { { "never", "Never" }, { "group", "Joining a group" }, { "instance", "New instance" }, { "combat", "Entering combat" } }, x2, y); y = y - ROW - 4
  slider(frame, "Row height", "rowHeight", 10, 24, 1, x1, y); slider(frame, "Font size", "fontSize", 7, 16, 1, x2, y); y = y - 28
  slider(frame, "Bar opacity", "barAlpha", .1, 1, .05, x1, y); slider(frame, "Background opacity", "backdropAlpha", 0, 1, .05, x2, y); y = y - 28
  slider(frame, "Opacity in combat", "fightOpacity", .1, 1, .05, x1, y); slider(frame, "Opacity out of combat", "idleOpacity", .1, 1, .05, x2, y); y = y - 28
  slider(frame, "Fights kept", "historySize", 1, 20, 1, x1, y); slider(frame, "Report lines", "reportRows", 1, 15, 1, x2, y); y = y - 28
  frame:SetHeight(-y + 10)
  frame:Hide()
end

function C.Toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide(); return end
  for i = 1, getn(widgets) do widgets[i]:Refresh() end
  frame:Show()
end
