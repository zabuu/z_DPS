-- zDPS: the meter window. One frame, pooled rows, a 0.5s refresh that only runs
-- while the window is shown and something changed (or a fight is running).
local Z = zDPS
local U = {}
Z.UI = U

local D = Z.Data
local getn, floor, format, max, min = table.getn, math.floor, string.format, math.max, math.min
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"

U.colors = {
  bg = { .04, .05, .07 }, border = { .18, .22, .28 }, title = { .08, .1, .13 },
  text = { .92, .94, .97 }, muted = { .6, .66, .74 }, accent = { .2, .78, .68 },
  spell = { .27, .5, .78 }, detail = { .45, .45, .52 }, pet = { .6, .5, .35 }, threat = { .78, .35, .25 },
}
local CLASS_FALLBACK = { r = .6, g = .6, b = .6 }

local frame, title, rows, grip, menu
rows = {}
local rowBuf = {}          -- rows handed to Data
local view = { level = 1, player = nil, key = nil, field = nil, offset = 0 }
local dirty = true
local nextRefresh = 0
local shown = false

-- Formatting ------------------------------------------------------------------------
function U.FormatNumber(v)
  if not v then return "0" end
  if Z.db.shortNumbers then
    if v >= 1000000 then return format("%.2fm", v / 1000000) end
    if v >= 100000 then return format("%.0fk", v / 1000) end
    if v >= 10000 then return format("%.1fk", v / 1000) end
  end
  if v >= 100 or v == floor(v) then return format("%d", floor(v + .5)) end
  return format("%.1f", v)
end

local function fmtTime(sec)
  sec = floor(sec)
  return format("%d:%02d", floor(sec / 60), sec - floor(sec / 60) * 60)
end

local function classColor(class)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  if class == "PET" then return U.colors.pet[1], U.colors.pet[2], U.colors.pet[3] end
  return CLASS_FALLBACK.r, CLASS_FALLBACK.g, CLASS_FALLBACK.b
end

-- Widgets ----------------------------------------------------------------------------
local function surface(f, color, alpha)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
  f:SetBackdropBorderColor(U.colors.border[1], U.colors.border[2], U.colors.border[3], 1)
end

local function font(fs, size, color)
  if not fs:SetFont(FONT, size or 10, "") and fs.SetFontObject then fs:SetFontObject(GameFontHighlightSmall) end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, .9); fs:SetShadowOffset(1, -1) end
  color = color or U.colors.text
  fs:SetTextColor(color[1], color[2], color[3], 1)
end

local function tinyButton(parent, label, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(11); b:SetHeight(11)
  b.text = b:CreateFontString(nil, "OVERLAY")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  font(b.text, 9, U.colors.muted)
  b.text:SetText(label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function()
    this.text:SetTextColor(U.colors.text[1], U.colors.text[2], U.colors.text[3])
    if tip then GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT"); GameTooltip:SetText(tip, 1, 1, 1); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function()
    this.text:SetTextColor(U.colors.muted[1], U.colors.muted[2], U.colors.muted[3]); GameTooltip:Hide()
  end)
  return b
end

local function mouseOver(f)
  local x, y = GetCursorPosition()
  local s = f:GetEffectiveScale()
  x, y = x / s, y / s
  local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  return l and x >= l - 2 and x <= r + 2 and y >= b - 2 and y <= t + 2
end

-- Menu: one pooled dropdown reused by every menu on the window.
local menuItems = {}
local function getMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", "zDPSMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP"); menu:EnableMouse(true); surface(menu, U.colors.bg, .97)
  menu:Hide(); menu.n = 0
  menu:SetScript("OnUpdate", function()
    -- close when the cursor leaves the menu and its anchor
    if not mouseOver(this) and (not this.anchor or not mouseOver(this.anchor)) then
      this.away = (this.away or 0) + arg1
      if this.away > .6 then this:Hide() end
    else this.away = 0 end
  end)
  return menu
end

local function menuClear() local m = getMenu(); m.n = 0; m.away = 0 end
local function menuAdd(text, fn, checked, header)
  local m = getMenu()
  m.n = m.n + 1
  local item = menuItems[m.n]
  if not item then
    item = CreateFrame("Button", nil, m)
    item:SetHeight(13)
    item.text = item:CreateFontString(nil, "OVERLAY")
    item.text:SetPoint("LEFT", item, "LEFT", 5, 0); item.text:SetJustifyH("LEFT")
    item.hl = item:CreateTexture(nil, "BACKGROUND"); item.hl:SetTexture(WHITE); item.hl:SetAllPoints(item)
    item.hl:SetVertexColor(U.colors.accent[1], U.colors.accent[2], U.colors.accent[3], .18); item.hl:Hide()
    item:SetScript("OnEnter", function() if this.fn then this.hl:Show() end end)
    item:SetScript("OnLeave", function() this.hl:Hide() end)
    item:SetScript("OnClick", function() if this.fn then this.fn(); m:Hide() end end)
    menuItems[m.n] = item
  end
  item.fn = fn
  font(item.text, Z.db.fontSize, header and U.colors.muted or (checked and U.colors.accent or U.colors.text))
  item.text:SetText(text)
  item:Show()
  return item
end
local function menuOpen(anchor)
  local m = getMenu()
  local width = 90
  for i = 1, m.n do width = max(width, menuItems[i].text:GetStringWidth() + 12) end
  for i = 1, m.n do
    local item = menuItems[i]
    item:SetWidth(width)
    item:ClearAllPoints(); item:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -2 - (i - 1) * 13)
  end
  for i = m.n + 1, getn(menuItems) do menuItems[i]:Hide() end
  m:SetWidth(width + 2); m:SetHeight(m.n * 13 + 4)
  m.anchor = anchor
  m:ClearAllPoints(); m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
  m:Show()
end

-- Rows --------------------------------------------------------------------------------
local function onRowClick()
  local r = this.row
  if not r then return end
  if arg1 == "RightButton" then U.Back(); return end
  if view.level == 1 and r.kind == "player" then
    view.level = 2; view.player = r.key; view.offset = 0
  elseif view.level == 2 and r.kind ~= "player" and r.kind ~= "threat" then
    local metric = D.metricByKey[Z.db.metric]
    if metric and metric.detail then view.level = 3; view.key = r.key; view.field = r.kind; view.offset = 0 end
  end
  dirty = true; U.Refresh()
end

local function onRowEnter()
  local r = this.row
  if not r or view.level ~= 1 or r.kind ~= "player" then return end
  local seg = U.Segment()
  local metric = D.metricByKey[Z.db.metric]
  local p = seg and seg.players[r.key]
  if not p or not metric or not metric.rows then return end
  local buf = U.tipBuf or {}; U.tipBuf = buf
  metric.rows(p, seg, buf)
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText(r.key, 1, 1, 1)
  local sum = 0
  for i = 1, buf.n or 0 do sum = sum + buf[i].value end
  for i = 1, min(buf.n or 0, 5) do
    local b = buf[i]
    GameTooltip:AddDoubleLine(b.name, format("%s  %.0f%%", U.FormatNumber(b.value), sum > 0 and b.value / sum * 100 or 0), .85, .85, .85, 1, 1, 1)
  end
  GameTooltip:Show()
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, frame)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetTexture(WHITE)
  r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetPoint("LEFT", r, "LEFT", 3, 0); r.name:SetJustifyH("LEFT")
  r.value = r:CreateFontString(nil, "OVERLAY"); r.value:SetPoint("RIGHT", r, "RIGHT", -3, 0); r.value:SetJustifyH("RIGHT")
  r:SetScript("OnClick", onRowClick)
  r:SetScript("OnEnter", onRowEnter)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rows[i] = r
  return r
end

local function layoutRows()
  local rh = Z.db.rowHeight
  local top = Z.db.showTitle and (rh + 1) or 1
  local count = floor((frame:GetHeight() - top - 1) / rh)
  U.visible = max(count, 1)
  for i = 1, U.visible do
    local r = getRow(i)
    r:SetHeight(rh - 1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -top - (i - 1) * rh)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -top - (i - 1) * rh)
    font(r.name, Z.db.fontSize); font(r.value, Z.db.fontSize)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
  end
  for i = U.visible + 1, getn(rows) do rows[i]:Hide() end
end

-- State -------------------------------------------------------------------------------
function U.Segment()
  local mode = Z.db.mode
  if mode == "total" then return D.total end
  if type(mode) == "number" then return D.history[mode] or D.current end
  return D.current
end

function U.IsThreatVisible() return shown and Z.db.metric == "threat" end
function U.Dirty() dirty = true end

function U.Back()
  if view.level == 1 then return end
  view.level = view.level - 1; view.offset = 0
  dirty = true; U.Refresh()
end

local function modeLabel()
  local mode = Z.db.mode
  if mode == "total" then return "Total" end
  if type(mode) == "number" then local seg = D.history[mode]; return seg and (seg.target or "Fight") or "Current" end
  return "Current"
end

-- Refresh ----------------------------------------------------------------------------------
local function paintRow(f, r, maxValue, color, text, cr, cg, cb)
  f.row = r
  f.name:SetText(text)
  f.value:SetText(r.text or "")
  local w = f:GetWidth()
  local frac = maxValue > 0 and (r.value or 0) / maxValue or 0
  f.bar:SetWidth(max(frac * w, 1))
  f.bar:SetVertexColor(cr, cg, cb, Z.db.barAlpha)
  f:Show()
end

local function playerRows(seg, metric)
  local sum = D.PlayerRows(seg, metric, rowBuf)
  for i = 1, rowBuf.n do
    local r = rowBuf[i]
    if metric.count then r.text = format("%d", r.value)
    elseif Z.db.showPercent and sum > 0 then r.text = format("%s  %.0f%%", U.FormatNumber(r.value), r.value / sum * 100)
    else r.text = U.FormatNumber(r.value) end
  end
  return sum
end

function U.Refresh()
  if not shown then return end
  dirty = false
  local metric = D.metricByKey[Z.db.metric] or D.metrics[1]
  local seg = U.Segment()
  local list, sum = rowBuf, 0
  local header
  if metric.threat then
    list = Z.Threat.rows
    header = "Threat · "..(Z.Threat.target or "no target")
    for i = 1, list.n or 0 do local r = list[i]; r.text = format("%s  %d%%%s", U.FormatNumber(r.value), r.perc, r.tank and "  T" or "") end
  elseif view.level == 1 then
    playerRows(seg, metric)
    header = metric.label.." · "..modeLabel()
    if seg then header = header.."  "..fmtTime(D.Duration(seg)) end
  else
    local p = seg and seg.players[view.player]
    if not p then view.level = 1; return U.Refresh() end
    if view.level == 2 then
      header = view.player.." · "..metric.label
      if metric.rows then metric.rows(p, seg, rowBuf) else rowBuf.n = 0 end
      sum = 0
      for i = 1, rowBuf.n do sum = sum + rowBuf[i].value end
      for i = 1, rowBuf.n do
        local r = rowBuf[i]
        if metric.count then
          local cat = metric.category and metric.category(r.key)
          r.text = cat and format("%d  %s", r.value, cat) or format("%d", r.value)
        else r.text = format("%s  %.0f%%", U.FormatNumber(r.value), sum > 0 and r.value / sum * 100 or 0) end
      end
    else
      header = view.player.." · "..view.key
      metric.detail(p, view.field, view.key, rowBuf)
    end
  end
  if Z.db.showTitle then title.text:SetText(header) end
  local n = list.n or 0
  if view.offset > max(n - U.visible, 0) then view.offset = max(n - U.visible, 0) end
  local maxValue = n > 0 and list[1 + view.offset] and list[1 + view.offset].value or 0
  if view.level == 3 then maxValue = 0; for i = 1, n do if list[i].value and list[i].value > maxValue then maxValue = list[i].value end end end
  for i = 1, U.visible do
    local f = rows[i]
    local r = list[i + view.offset]
    if r and r.value then
      local cr, cg, cb
      local text = r.name
      if view.level == 1 or metric.threat then
        if Z.db.classColors then cr, cg, cb = classColor(r.class) else cr, cg, cb = U.colors.accent[1], U.colors.accent[2], U.colors.accent[3] end
        if metric.threat then cr, cg, cb = U.colors.threat[1], U.colors.threat[2], U.colors.threat[3]; if r.tank then cr, cg, cb = classColor(r.class) end end
        if Z.db.showRank then text = (i + view.offset)..". "..text end
      elseif view.level == 2 then cr, cg, cb = U.colors.spell[1], U.colors.spell[2], U.colors.spell[3]
      else cr, cg, cb = U.colors.detail[1], U.colors.detail[2], U.colors.detail[3] end
      paintRow(f, r, maxValue, nil, text, cr, cg, cb)
    else
      f.row = nil; f:Hide()
    end
  end
  if n == 0 and rows[1] then
    local f = rows[1]
    f.row = nil; f.name:SetText(metric.threat and "no threat data" or (seg and "no data" or "no fight yet")); f.value:SetText("")
    f.bar:SetWidth(1); f:Show()
  end
end

-- Introspection used by tests and other addons.
function U.RowAt(i) local f = rows[i]; return f and f.row or nil end
function U.Title() return title and title.text:GetText() end
function U.ClickRow(i, button) local f = rows[i]; if f then this = f; arg1 = button or "LeftButton"; onRowClick() end end
function U.View() return view end

-- Modes / metrics ------------------------------------------------------------------------
function U.SetMetric(key)
  if not D.metricByKey[key] then Z.Print("unknown metric: "..tostring(key)); return end
  local wasThreat = Z.db.metric == "threat"
  Z.db.metric = key
  view.level = 1; view.offset = 0
  if key == "threat" then Z.Threat.Start() elseif wasThreat then Z.Threat.Stop() end
  dirty = true; U.Refresh()
end

function U.SetMode(mode)
  if mode == "total" then Z.db.mode = "total"
  elseif type(mode) == "number" then Z.db.mode = mode
  else Z.db.mode = "current" end
  view.level = 1; view.offset = 0
  dirty = true; U.Refresh()
end

local function openMetricMenu()
  menuClear()
  for i = 1, getn(D.metrics) do
    local m = D.metrics[i]
    menuAdd(m.label, function() U.SetMetric(m.key) end, Z.db.metric == m.key)
  end
  menuOpen(title)
end

local function openModeMenu()
  menuClear()
  menuAdd("Current fight", function() U.SetMode("current") end, Z.db.mode == "current")
  menuAdd("Total", function() U.SetMode("total") end, Z.db.mode == "total")
  for i = 1, getn(D.history) do
    local seg = D.history[i]
    local idx = i
    menuAdd(format("%s  %s", seg.target or "Fight", fmtTime(D.Duration(seg))), function() U.SetMode(idx) end, Z.db.mode == i)
  end
  menuAdd("—", nil, false, true)
  menuAdd("Report to party", function() U.Report("party") end)
  menuAdd("Report to raid", function() U.Report("raid") end)
  menuAdd("Report to say", function() U.Report("say") end)
  menuOpen(title)
end

-- Report ------------------------------------------------------------------------------------
function U.Report(target)
  local metric = D.metricByKey[Z.db.metric] or D.metrics[1]
  local seg = U.Segment()
  local list = rowBuf
  if metric.threat then list = Z.Threat.rows else playerRows(seg, metric) end
  local n = min(list.n or 0, Z.db.reportRows or 5)
  if n == 0 then Z.Print("nothing to report"); return end
  local channel, who = "PARTY", nil
  target = target or (GetNumRaidMembers() > 0 and "raid" or "party")
  if target == "raid" then channel = "RAID" elseif target == "say" then channel = "SAY" elseif target == "party" then channel = "PARTY"
  else channel = "WHISPER"; who = target end
  local head = format("zDPS %s (%s%s)", metric.label, modeLabel(), seg and (", "..fmtTime(D.Duration(seg))) or "")
  SendChatMessage(head, channel, nil, who)
  for i = 1, n do
    local r = list[i]
    SendChatMessage(format("%d. %s  %s", i, r.name, r.text or U.FormatNumber(r.value)), channel, nil, who)
  end
end

-- Window -----------------------------------------------------------------------------------------
local function savePosition()
  Z.db.x = frame:GetLeft(); Z.db.y = frame:GetTop()
  Z.db.width = frame:GetWidth(); Z.db.height = frame:GetHeight()
end

function U.ApplySettings()
  local db = Z.db
  surface(frame, U.colors.bg, db.backdropAlpha)
  frame:SetWidth(db.width); frame:SetHeight(db.height)
  frame:ClearAllPoints()
  if db.x and db.y and db.point == "TOPLEFT" then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
  else frame:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0) end
  frame:SetMovable(not db.locked); frame:SetResizable(not db.locked)
  if db.locked then grip:Hide() else grip:Show() end
  frame.titleBar:SetHeight(db.rowHeight)
  if db.showTitle then frame.titleBar:Show() else frame.titleBar:Hide() end
  font(title.text, db.fontSize)
  frame.lock.text:SetText(db.locked and "L" or "l")
  frame:SetAlpha(Z.inFight and db.fightOpacity or db.idleOpacity)
  layoutRows()
  dirty = true
  U.Refresh()
end

function U.OnCombat(inFight)
  if not frame then return end
  frame:SetAlpha(inFight and Z.db.fightOpacity or Z.db.idleOpacity)
  if Z.db.hideOutOfCombat then if inFight then U.Show() else U.Hide() end end
  dirty = true
end

function U.Show() frame:Show() end
function U.Hide() frame:Hide() end
function U.Toggle() if frame:IsShown() then U.Hide() else U.Show() end end

function U.Init()
  frame = CreateFrame("Frame", "zDPSFrame", UIParent)
  U.frame = frame
  frame:SetFrameStrata("LOW")
  frame:SetMinResize(90, 40)
  frame:EnableMouse(true); frame:EnableMouseWheel(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() if not Z.db.locked then this:StartMoving() end end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); Z.db.point = "TOPLEFT"; savePosition() end)
  frame:SetScript("OnMouseWheel", function()
    local n = (rowBuf.n or 0)
    if Z.db.metric == "threat" then n = Z.Threat.rows.n or 0 end
    if arg1 > 0 then view.offset = max(view.offset - 1, 0) else view.offset = min(view.offset + 1, max(n - U.visible, 0)) end
    dirty = true; U.Refresh()
  end)
  frame:SetScript("OnShow", function() shown = true; dirty = true; nextRefresh = 0; if Z.db.metric == "threat" then Z.Threat.Start() end end)
  frame:SetScript("OnHide", function() shown = false; Z.Threat.Stop(); if menu then menu:Hide() end end)
  frame:SetScript("OnUpdate", function()
    local now = GetTime()
    if now < nextRefresh then return end
    nextRefresh = now + .5
    if dirty or Z.inFight or Z.db.metric == "threat" then U.Refresh() end
  end)

  local bar = CreateFrame("Frame", nil, frame)
  frame.titleBar = bar
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND"); bar.bg:SetTexture(WHITE); bar.bg:SetAllPoints(bar)
  bar.bg:SetVertexColor(U.colors.title[1], U.colors.title[2], U.colors.title[3], 1)
  title = CreateFrame("Button", nil, bar)
  title:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); title:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -38, 0)
  title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  title.text = title:CreateFontString(nil, "OVERLAY")
  title.text:SetPoint("LEFT", title, "LEFT", 3, 0); title.text:SetPoint("RIGHT", title, "RIGHT", 0, 0); title.text:SetJustifyH("LEFT")
  title:SetScript("OnClick", function()
    if view.level > 1 then U.Back(); return end
    if arg1 == "RightButton" then openModeMenu() else openMetricMenu() end
  end)
  title:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(view.level > 1 and "Click: back" or "Left: metric  ·  Right: fight / report", .9, .9, .9); GameTooltip:Show()
  end)
  title:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Register drag on the title too so moving works from the bar when rows cover the body.
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() if not Z.db.locked then frame:StartMoving() end end)
  title:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); Z.db.point = "TOPLEFT"; savePosition() end)

  frame.reset = tinyButton(bar, "r", "Reset (shift: total only)", function()
    if IsShiftKeyDown() then D.ResetTotal() else D.ResetAll() end
    view.level = 1; dirty = true; U.Refresh()
  end)
  frame.reset:SetPoint("RIGHT", bar, "RIGHT", -25, 0)
  frame.config = tinyButton(bar, "c", "Settings", function() Z.Config.Toggle() end)
  frame.config:SetPoint("RIGHT", bar, "RIGHT", -13, 0)
  frame.lock = tinyButton(bar, "l", "Lock / unlock", function()
    Z.db.locked = not Z.db.locked; U.ApplySettings()
  end)
  frame.lock:SetPoint("RIGHT", bar, "RIGHT", -1, 0)

  grip = CreateFrame("Button", nil, frame)
  grip:SetWidth(9); grip:SetHeight(9)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  grip.tex = grip:CreateTexture(nil, "OVERLAY"); grip.tex:SetTexture(WHITE); grip.tex:SetAllPoints(grip)
  grip.tex:SetVertexColor(U.colors.border[1], U.colors.border[2], U.colors.border[3], .9)
  grip:SetScript("OnMouseDown", function() if not Z.db.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); savePosition(); layoutRows(); dirty = true; U.Refresh() end)
  frame:SetScript("OnSizeChanged", function() if shown then layoutRows() end end)

  shown = true
  U.ApplySettings()
  frame:Show()
end
