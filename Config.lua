-- zDPS: settings window. Built on first open; plain checkboxes, sliders, cycle
-- buttons and colour swatches on one compact surface.
--
-- The picker at the top chooses what the window-level settings apply to: all
-- windows, or one window. A window keeps only the settings it was given
-- (zDPSDB.windows[i].over); everything else follows the all-windows value.
-- Settings that decide how numbers are counted are shared and greyed out while
-- one window is picked.
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
local target   -- nil: all windows; otherwise a window index

-- every font string made here is remembered so the outline setting can be re-applied;
-- the drop shadow is dropped while an outline is on, so the text doesn't look doubled
local fonts = {}
local function setFont(fs)
  local flags = Z.FontFlags()
  fs:SetFont(FONT, fs.zSize, flags)
  if fs.SetShadowColor then
    fs:SetShadowColor(0, 0, 0, .9)
    if flags == "" then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
  end
end
local function font(fs, size, muted)
  if not fs.zSize then table.insert(fonts, fs) end
  fs.zSize = size or 10
  setFont(fs)
  local c = muted and Z.UI.colors.muted or Z.UI.colors.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
end
function C.ApplyFonts() for i = 1, getn(fonts) do setFont(fonts[i]) end end

-- Reading and writing a setting for the current picker choice --------------------------
local function windowDb() return target and Z.db.windows and Z.db.windows[target] end
local function shared(key) return target and not Z.isWindowKey[key] end
local function own(key)
  local w = windowDb()
  return w and w.over and w.over[key] ~= nil
end
function C.Get(key)
  local w = windowDb()
  if w and Z.isWindowKey[key] and w.over and w.over[key] ~= nil then return w.over[key] end
  return Z.db[key]
end
function C.Set(key, v)
  local w = windowDb()
  if w and Z.isWindowKey[key] then
    w.over = w.over or {}
    w.over[key] = Z.Copy(v)
  else
    Z.db[key] = v
  end
end
local function clear(key)
  local w = windowDb()
  if w and w.over then w.over[key] = nil; if not next(w.over) then w.over = nil end end
end

local function apply()
  Z.UI.ApplySettings()
end

local function refreshAll()
  for i = 1, getn(widgets) do widgets[i]:Refresh() end
end

-- Label colour: this window's own setting in accent, shared settings dimmed while a window is picked.
local function paintLabel(fs, key, muted)
  local c = muted and Z.UI.colors.muted or Z.UI.colors.text
  if own(key) then c = Z.UI.colors.accent end
  fs:SetTextColor(c[1], c[2], c[3], shared(key) and .35 or 1)
end

-- Right-click on a window's own setting goes back to the all-windows value.
local function rightClickClears(f, key)
  if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  return function()
    if arg1 == "RightButton" then
      if own(key) then clear(key); refreshAll(); apply() end
      return true
    end
  end
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
  local right = rightClickClears(b.hit, key)
  b.hit:SetScript("OnClick", function()
    if right() or shared(key) then return end
    C.Set(key, not C.Get(key))
    b:Refresh()
    if onChange then onChange() else apply() end
  end)
  b.Refresh = function(self) self:SetChecked(C.Get(key)); paintLabel(self.text, key) end
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
  local function show(v) s.value:SetText(step < 1 and format("%.2f", v) or format("%d", v)) end
  s:SetScript("OnValueChanged", function()
    if this.updating then return end
    if shared(key) then this:Refresh(); return end
    local v = this:GetValue()
    v = floor(v / step + .5) * step
    if C.Get(key) ~= v then C.Set(key, v); show(v); paintLabel(this.text, key); apply() end
  end)
  -- right-click the label area to go back to the all-windows value
  s.hit = CreateFrame("Button", nil, s); s.hit:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 1); s.hit:SetWidth(width or 110); s.hit:SetHeight(11)
  local right = rightClickClears(s.hit, key)
  s.hit:SetScript("OnClick", function() right() end)
  s.Refresh = function(self)
    self.updating = true; self:SetValue(C.Get(key)); self.updating = false
    show(C.Get(key)); paintLabel(self.text, key)
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
    paintLabel(self.text, key, true)
    self.value:SetAlpha(shared(key) and .35 or 1)
    local v = C.Get(key)
    for i = 1, getn(values) do if values[i][1] == v then self.value:SetText(values[i][2]); return end end
    self.value:SetText(tostring(v))
  end
  local right = rightClickClears(b, key)
  b:SetScript("OnClick", function()
    if right() or shared(key) then return end
    local idx, v = 1, C.Get(key)
    for i = 1, getn(values) do if values[i][1] == v then idx = i end end
    idx = idx + 1; if idx > getn(values) then idx = 1 end
    C.Set(key, values[idx][1]); b:Refresh(); if onChange then onChange() else apply() end
  end)
  table.insert(widgets, b)
  return b
end

-- Colour swatch: opens the game's colour picker. withAlpha adds its opacity slider
-- (the slider reads as transparency, so alpha = 1 - value).
local function swatch(parent, label, key, x, y, withAlpha)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(COL - 8); b:SetHeight(ROW - 3)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b.box = CreateFrame("Frame", nil, b); b.box:SetWidth(11); b.box:SetHeight(11); b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  b.box:SetBackdropBorderColor(.3, .36, .44, 1)
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetPoint("LEFT", b.box, "RIGHT", 4, 0); font(b.text); b.text:SetText(label)
  b.Refresh = function(self)
    local c = C.Get(key)
    self.box:SetBackdropColor(c[1], c[2], c[3], withAlpha and (c[4] or 1) or 1)
    paintLabel(self.text, key)
  end
  local right = rightClickClears(b, key)
  b:SetScript("OnClick", function()
    if right() then return end
    local old = Z.Copy(C.Get(key))
    local function set(r, g, bl, a)
      C.Set(key, { r, g, bl, a }); b:Refresh(); apply()
    end
    ColorPickerFrame.func = function()
      local r, g, bl = ColorPickerFrame:GetColorRGB()
      set(r, g, bl, withAlpha and (1 - OpacitySliderFrame:GetValue()) or nil)
    end
    ColorPickerFrame.opacityFunc = ColorPickerFrame.func
    ColorPickerFrame.cancelFunc = function() set(old[1], old[2], old[3], old[4]) end
    ColorPickerFrame.hasOpacity = withAlpha and 1 or nil
    ColorPickerFrame.opacity = 1 - (old[4] or 1)
    ColorPickerFrame:SetColorRGB(old[1], old[2], old[3])
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ShowUIPanel(ColorPickerFrame)
  end)
  table.insert(widgets, b)
  return b
end

local function heading(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY"); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); font(fs, 10, true)
  fs:SetText(text)
  return fs
end

-- The picker: All windows, then each window by number and what it shows.
local function targetLabel()
  if not target then return "All windows" end
  local w = Z.UI.windows[target]
  local m = w and Z.UI.Metric(w)
  return format("Window %d%s", target, m and (" ("..m.label..")") or "")
end

local function setTarget(index)
  if index and not Z.UI.windows[index] then index = nil end
  target = index
  frame.picker.value:SetText(targetLabel())
  if target then frame.reset:Show(); frame.hint:Show() else frame.reset:Hide(); frame.hint:Hide() end
  refreshAll()
end

local function build()
  frame = CreateFrame("Frame", "zDPSConfig", UIParent)
  frame:SetWidth(COL * 2 + 16); frame:SetHeight(238)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  -- windows set to show only in combat stay up while this is open
  frame:SetScript("OnShow", function() Z.UI.UpdateVisibility() end)
  frame:SetScript("OnHide", function() Z.UI.UpdateVisibility() end)
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

  local x1, x2, y = 8, COL + 8, -24
  -- picker
  local p = CreateFrame("Button", nil, frame)
  frame.picker = p
  p:SetWidth(COL * 2 - 8); p:SetHeight(ROW - 2)
  p:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, y)
  p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  p:SetBackdropColor(.09, .11, .14, 1); local a = Z.UI.colors.accent; p:SetBackdropBorderColor(a[1], a[2], a[3], .8)
  p.text = p:CreateFontString(nil, "OVERLAY"); p.text:SetPoint("LEFT", p, "LEFT", 4, 0); font(p.text, 10, true); p.text:SetText("Settings for")
  p.value = p:CreateFontString(nil, "OVERLAY"); p.value:SetPoint("RIGHT", p, "RIGHT", -4, 0); font(p.value)
  p:SetScript("OnClick", function()
    local n = getn(Z.UI.windows)
    if not target then setTarget(n > 0 and 1 or nil) elseif target >= n then setTarget(nil) else setTarget(target + 1) end
  end)
  y = y - ROW - 4

  heading(frame, "Window", x1, y); heading(frame, "Tracking", x2, y); y = y - ROW
  check(frame, "Show title bar", "showTitle", x1, y)
  check(frame, "Merge pets into owner", "mergePets", x2, y, function() Z.Data.ResetAll(); apply() end); y = y - ROW
  check(frame, "Class colours", "classColors", x1, y)
  check(frame, "Short numbers (1.2k)", "shortNumbers", x2, y); y = y - ROW
  check(frame, "Class icons", "classIcons", x1, y)
  check(frame, "Locked", "locked", x2, y); y = y - ROW
  check(frame, "Show percent", "showPercent", x1, y)
  cycle(frame, "DPS time", "dpsTime", { { "fight", "Fight" }, { "active", "Active" } }, x2, y); y = y - ROW
  check(frame, "Rank numbers", "showRank", x1, y)
  cycle(frame, "Reset total", "resetTotal", { { "never", "Never" }, { "group", "Joining a group" }, { "instance", "New instance" }, { "combat", "Entering combat" } }, x2, y); y = y - ROW
  check(frame, "Per second in Damage/Healing", "showPerSecond", x1, y); y = y - ROW - 1
  cycle(frame, "Show", "show", { { "always", "Always" }, { "combat", "In combat" }, { "linger", "In combat +5s" } }, x1, y)
  cycle(frame, "Text outline", "outline", { { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" } }, x2, y); y = y - ROW - 4

  heading(frame, "Colours", x1, y); y = y - ROW
  swatch(frame, "Background", "bgColor", x1, y, true)
  swatch(frame, "Title bar", "titleColor", x2, y, true); y = y - ROW
  swatch(frame, "Border", "borderColor", x1, y, true)
  swatch(frame, "Text", "textColor", x2, y); y = y - ROW
  swatch(frame, "Bars (class colours off)", "barColor", x1, y); y = y - ROW - 2

  slider(frame, "Row height", "rowHeight", 10, 24, 1, x1, y); slider(frame, "Font size", "fontSize", 7, 16, 1, x2, y); y = y - 28
  slider(frame, "Bar opacity", "barAlpha", .1, 1, .05, x1, y); y = y - 28
  slider(frame, "Opacity in combat", "fightOpacity", .1, 1, .05, x1, y); slider(frame, "Opacity out of combat", "idleOpacity", .1, 1, .05, x2, y); y = y - 28
  slider(frame, "Fights kept", "historySize", 1, 20, 1, x1, y); slider(frame, "Report lines", "reportRows", 1, 15, 1, x2, y); y = y - 26

  -- shown while one window is picked
  frame.hint = frame:CreateFontString(nil, "OVERLAY"); frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, y); font(frame.hint, 9, true)
  frame.hint:SetWidth(COL * 2 - 70); frame.hint:SetJustifyH("LEFT")
  frame.hint:SetText("Highlighted: this window's own setting. Right-click one to use the all-windows setting again.")
  local r = CreateFrame("Button", nil, frame)
  frame.reset = r
  r:SetWidth(56); r:SetHeight(ROW - 2); r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, y)
  r:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  r:SetBackdropColor(.09, .11, .14, 1); r:SetBackdropBorderColor(.3, .36, .44, 1)
  r.text = r:CreateFontString(nil, "OVERLAY"); r.text:SetPoint("CENTER", r, "CENTER", 0, 0); font(r.text, 9); r.text:SetText("Reset window")
  r:SetScript("OnClick", function()
    local w = windowDb()
    if w then w.over = nil; refreshAll(); apply() end
  end)
  y = y - 24
  frame:SetHeight(-y + 4)
  frame:Hide()
end

-- Toggle(index): open for one window (the gear on that window), or for all windows.
-- Clicking another window's gear while open switches to that window instead of closing.
function C.Toggle(index)
  if not frame then build() end
  if frame:IsShown() and index == target then frame:Hide(); return end
  setTarget(index)
  frame:Show()
end

function C.IsShown() return frame and frame:IsShown() end
function C.Target() return target end
