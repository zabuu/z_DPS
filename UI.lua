-- zDPS: meter windows. Any number of windows, each with its own metric and
-- fight selection; pooled rows; one 0.5s refresh that only runs while a window
-- is shown and something changed (or a fight is running).
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
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
U.CLASS_COORDS = {
  WARRIOR = { 0, .25, 0, .25 }, MAGE = { .25, .5, 0, .25 }, ROGUE = { .5, .75, 0, .25 }, DRUID = { .75, 1, 0, .25 },
  HUNTER = { 0, .25, .25, .5 }, SHAMAN = { .25, .5, .25, .5 }, PRIEST = { .5, .75, .25, .5 }, WARLOCK = { .75, 1, .25, .5 },
  PALADIN = { 0, .25, .5, .75 },
}
local PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"
-- Title bar glyphs: {texture, l, r, t, b}
local GLYPH = {
  add = { "Interface\\Buttons\\UI-PlusButton-Up", .2, .8, .2, .8 },
  reset = { "Interface\\Buttons\\UI-RotationLeft-Button-Up", .2, .8, .2, .8 },
  config = { "Interface\\Icons\\Trade_Engineering", .1, .9, .1, .9 },
  locked = { "Interface\\Buttons\\LockButton-Locked-Up", .2, .8, .2, .8 },
  unlocked = { "Interface\\Buttons\\LockButton-Unlocked-Up", .2, .8, .2, .8 },
  close = { "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", .2, .8, .2, .8 },
}

U.windows = {}
local menu, menuItems = nil, {}
local dirty = true
local nextRefresh = 0

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

function U.SetClassIcon(tex, class)
  local c = U.CLASS_COORDS[class]
  if c then tex:SetTexture(CLASS_TEX); tex:SetTexCoord(c[1], c[2], c[3], c[4]); return true end
  if class == "PET" then tex:SetTexture(PET_ICON); tex:SetTexCoord(.07, .93, .07, .93); return true end
  return false
end

-- Widgets ----------------------------------------------------------------------------
local function surface(f, color, alpha)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
  f:SetBackdropBorderColor(U.colors.border[1], U.colors.border[2], U.colors.border[3], 1)
end

local function font(fs, size, color)
  if not fs:SetFont(FONT, size or 10, "") and fs.SetFontObject then fs:SetFontObject(GameFontHighlightSmall) end
  color = color or U.colors.text
  fs:SetTextColor(color[1], color[2], color[3], 1)
end

local function setGlyph(b, key)
  local g = GLYPH[key]
  b.icon:SetTexture(g[1]); b.icon:SetTexCoord(g[2], g[3], g[4], g[5])
end

local function glyphButton(parent, key, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(12); b:SetHeight(12)
  b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetAllPoints(b)
  b.icon:SetVertexColor(.75, .8, .88, 1)
  setGlyph(b, key)
  b.tip = tip
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function()
    this.icon:SetVertexColor(1, 1, 1, 1)
    if this.tip then GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT"); GameTooltip:SetText(this.tip, 1, 1, 1); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() this.icon:SetVertexColor(.75, .8, .88, 1); GameTooltip:Hide() end)
  return b
end

local function mouseOver(f)
  local x, y = GetCursorPosition()
  local s = f:GetEffectiveScale()
  x, y = x / s, y / s
  local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  return l and x >= l - 2 and x <= r + 2 and y >= b - 2 and y <= t + 2
end

-- Menu: one pooled dropdown shared by every window.
local function getMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", "zDPSMenu", UIParent)
  menu:SetFrameStrata("TOOLTIP"); menu:EnableMouse(true); surface(menu, U.colors.bg, .97)
  menu:Hide(); menu.n = 0
  menu:SetScript("OnUpdate", function()
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

-- Window state ------------------------------------------------------------------------
-- Z.db.windows[i] = {metric, mode, x, y, width, height, point}
local function windowSettings(i)
  Z.db.windows = Z.db.windows or {}
  local w = Z.db.windows[i]
  if not w then
    w = { metric = Z.db.metric or "dps", mode = "current", width = Z.db.width or 180, height = Z.db.height or 118 }
    if i == 1 and Z.db.point == "TOPLEFT" then w.point = "TOPLEFT"; w.x = Z.db.x; w.y = Z.db.y
    else w.point = "CENTER"; w.x = (Z.db.x or 260) + (i - 1) * 20; w.y = (Z.db.y or -120) - (i - 1) * 20 end
    Z.db.windows[i] = w
  end
  return w
end

function U.Segment(win)
  local mode = win and win.db.mode or "current"
  if mode == "total" then return D.total end
  if type(mode) == "number" then return D.history[mode] or D.current end
  return D.current
end

function U.Metric(win) return D.metricByKey[win.db.metric] or D.metrics[1] end

function U.IsThreatVisible()
  for i = 1, getn(U.windows) do
    local w = U.windows[i]
    if w.shown and w.db.metric == "threat" then return true end
  end
  return false
end
function U.Dirty() dirty = true end

local function modeLabel(win)
  local mode = win.db.mode
  if mode == "total" then return "Total" end
  if type(mode) == "number" then local seg = D.history[mode]; return seg and (seg.target or "Fight") or "Current" end
  return "Current"
end

-- Rows --------------------------------------------------------------------------------
local function onRowClick()
  local win, r = this.win, this.row
  if not r then return end
  if arg1 == "RightButton" then U.Back(win); return end
  if win.view.level == 1 and r.kind == "player" then
    if Z.Detail then Z.Detail.Open(r.key, win); return end
    win.view.level = 2; win.view.player = r.key; win.view.offset = 0
  elseif win.view.level == 2 and r.kind ~= "player" and r.kind ~= "threat" then
    local metric = U.Metric(win)
    if metric.detail then win.view.level = 3; win.view.key = r.key; win.view.field = r.kind; win.view.offset = 0 end
  end
  dirty = true; U.Refresh()
end

local function onRowEnter()
  local win, r = this.win, this.row
  if not r or win.view.level ~= 1 or r.kind ~= "player" then return end
  local seg = U.Segment(win)
  local metric = U.Metric(win)
  local p = seg and seg.players[r.key]
  if not p or not metric.rows then return end
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

local function getRow(win, i)
  local r = win.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, win.frame)
  r.win = win
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetTexture(WHITE)
  r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetPoint("LEFT", r, "LEFT", 3, 0); r.name:SetJustifyH("LEFT")
  r.value = r:CreateFontString(nil, "OVERLAY"); r.value:SetPoint("RIGHT", r, "RIGHT", -3, 0); r.value:SetJustifyH("RIGHT")
  r:SetScript("OnClick", onRowClick)
  r:SetScript("OnEnter", onRowEnter)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.rows[i] = r
  return r
end

local function layoutRows(win)
  local rh = Z.db.rowHeight
  local top = Z.db.showTitle and (rh + 1) or 1
  local count = floor((win.frame:GetHeight() - top - 1) / rh)
  win.visible = max(count, 1)
  for i = 1, win.visible do
    local r = getRow(win, i)
    r:SetHeight(rh - 1)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", win.frame, "TOPLEFT", 1, -top - (i - 1) * rh)
    r:SetPoint("TOPRIGHT", win.frame, "TOPRIGHT", -1, -top - (i - 1) * rh)
    font(r.name, Z.db.fontSize); font(r.value, Z.db.fontSize)
    r.icon:SetWidth(rh - 3); r.icon:SetHeight(rh - 3)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
    r:Show()
  end
  for i = win.visible + 1, getn(win.rows) do win.rows[i]:Hide() end
end

-- Refresh ----------------------------------------------------------------------------------
local function paintRow(f, r, maxValue, text, cr, cg, cb)
  f.row = r
  if Z.db.classIcons and r.class and U.SetClassIcon(f.icon, r.class) then
    f.icon:Show(); f.name:SetPoint("LEFT", f, "LEFT", Z.db.rowHeight + 1, 0)
  else
    f.icon:Hide(); f.name:SetPoint("LEFT", f, "LEFT", 3, 0)
  end
  f.name:SetText(text)
  f.value:SetText(r.text or "")
  local w = f:GetWidth()
  local frac = maxValue > 0 and (r.value or 0) / maxValue or 0
  f.bar:SetWidth(max(frac * w, 1))
  f.bar:SetVertexColor(cr, cg, cb, Z.db.barAlpha)
  f:Show()
end

local function playerRows(win, seg, metric)
  local rowBuf = win.rowBuf
  local sum = D.PlayerRows(seg, metric, rowBuf)
  for i = 1, rowBuf.n do
    local r = rowBuf[i]
    local v = U.FormatNumber(r.value)
    if metric.count then v = format("%d", r.value)
    elseif r.total then v = format("%s (%s)", v, U.FormatNumber(r.total)) end
    if not metric.count and Z.db.showPercent and sum > 0 then r.text = format("%s  %.0f%%", v, r.value / sum * 100)
    else r.text = v end
  end
  return sum
end

local function refreshWindow(win)
  local metric = U.Metric(win)
  local seg = U.Segment(win)
  local view, rowBuf = win.view, win.rowBuf
  local list, sum = rowBuf, 0
  local header
  if metric.threat then
    list = Z.Threat.rows
    header = "Threat · "..(Z.Threat.target or "no target")
    for i = 1, list.n or 0 do local r = list[i]; r.text = format("%s  %d%%%s", U.FormatNumber(r.value), r.perc, r.tank and "  T" or "") end
  elseif view.level == 1 then
    playerRows(win, seg, metric)
    header = metric.label.." · "..modeLabel(win)
    if seg then header = header.."  "..fmtTime(D.Duration(seg)) end
  else
    local p = seg and seg.players[view.player]
    if not p then view.level = 1; return refreshWindow(win) end
    if view.level == 2 then
      header = view.player.." · "..metric.label
      if metric.rows then metric.rows(p, seg, rowBuf) else rowBuf.n = 0 end
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
  if Z.db.showTitle then win.title.text:SetText(header) end
  local n = list.n or 0
  if view.offset > max(n - win.visible, 0) then view.offset = max(n - win.visible, 0) end
  local maxValue = n > 0 and list[1 + view.offset] and list[1 + view.offset].value or 0
  if view.level == 3 then maxValue = 0; for i = 1, n do if list[i].value and list[i].value > maxValue then maxValue = list[i].value end end end
  for i = 1, win.visible do
    local f = win.rows[i]
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
      paintRow(f, r, maxValue, text, cr, cg, cb)
    else
      f.row = nil; f:Hide()
    end
  end
  if n == 0 and win.rows[1] then
    local f = win.rows[1]
    f.row = nil; f.icon:Hide(); f.name:SetPoint("LEFT", f, "LEFT", 3, 0)
    f.name:SetText(metric.threat and "no threat data" or (seg and "no data" or "no fight yet")); f.value:SetText("")
    f.bar:SetWidth(1); f:Show()
  end
end

function U.Refresh()
  dirty = false
  for i = 1, getn(U.windows) do
    local win = U.windows[i]
    if win.shown then refreshWindow(win) end
  end
end

-- Navigation / modes ------------------------------------------------------------------------
function U.Back(win)
  win = win or U.windows[1]
  if win.view.level == 1 then return end
  win.view.level = win.view.level - 1; win.view.offset = 0
  dirty = true; U.Refresh()
end

function U.SetMetric(key, win)
  win = win or U.windows[1]
  if not D.metricByKey[key] then Z.Print("unknown metric: "..tostring(key)); return end
  win.db.metric = key
  if win == U.windows[1] then Z.db.metric = key end
  win.view.level = 1; win.view.offset = 0
  if U.IsThreatVisible() then Z.Threat.Start() else Z.Threat.Stop() end
  dirty = true; U.Refresh()
  if Z.Detail then Z.Detail.Tick(true) end
end

function U.SetMode(mode, win)
  win = win or U.windows[1]
  if mode == "total" then win.db.mode = "total"
  elseif type(mode) == "number" then win.db.mode = mode
  else win.db.mode = "current" end
  win.view.level = 1; win.view.offset = 0
  dirty = true; U.Refresh()
  if Z.Detail then Z.Detail.Tick(true) end
end

local function openMetricMenu(win)
  menuClear()
  for i = 1, getn(D.metrics) do
    local m = D.metrics[i]
    menuAdd(m.label, function() U.SetMetric(m.key, win) end, win.db.metric == m.key)
  end
  menuOpen(win.title)
end

local function openModeMenu(win)
  menuClear()
  menuAdd("Current fight", function() U.SetMode("current", win) end, win.db.mode == "current")
  menuAdd("Total", function() U.SetMode("total", win) end, win.db.mode == "total")
  for i = 1, getn(D.history) do
    local seg = D.history[i]
    local idx = i
    menuAdd(format("%s  %s", seg.target or "Fight", fmtTime(D.Duration(seg))), function() U.SetMode(idx, win) end, win.db.mode == i)
  end
  menuAdd("—", nil, false, true)
  menuAdd("Report to party", function() U.Report("party", win) end)
  menuAdd("Report to raid", function() U.Report("raid", win) end)
  menuAdd("Report to say", function() U.Report("say", win) end)
  menuOpen(win.title)
end

-- Report ------------------------------------------------------------------------------------
function U.Report(target, win)
  win = win or U.windows[1]
  local metric = U.Metric(win)
  local seg = U.Segment(win)
  local list = win.rowBuf
  if metric.threat then list = Z.Threat.rows else playerRows(win, seg, metric) end
  local n = min(list.n or 0, Z.db.reportRows or 5)
  if n == 0 then Z.Print("nothing to report"); return end
  local channel, who = "PARTY", nil
  target = target or (GetNumRaidMembers() > 0 and "raid" or "party")
  if target == "raid" then channel = "RAID" elseif target == "say" then channel = "SAY" elseif target == "party" then channel = "PARTY"
  else channel = "WHISPER"; who = target end
  local head = format("zDPS %s (%s%s)", metric.label, modeLabel(win), seg and (", "..fmtTime(D.Duration(seg))) or "")
  SendChatMessage(head, channel, nil, who)
  for i = 1, n do
    local r = list[i]
    SendChatMessage(format("%d. %s  %s", i, r.name, r.text or U.FormatNumber(r.value)), channel, nil, who)
  end
end

-- Windows -----------------------------------------------------------------------------------------
local function savePosition(win)
  local f = win.frame
  win.db.point = "TOPLEFT"; win.db.x = f:GetLeft(); win.db.y = f:GetTop()
  win.db.width = f:GetWidth(); win.db.height = f:GetHeight()
end

local function applyWindow(win)
  local db, f = Z.db, win.frame
  surface(f, U.colors.bg, db.backdropAlpha)
  f:SetWidth(win.db.width); f:SetHeight(win.db.height)
  f:ClearAllPoints()
  if win.db.point == "TOPLEFT" and win.db.x and win.db.y then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", win.db.x, win.db.y)
  else f:SetPoint("CENTER", UIParent, "CENTER", win.db.x or 0, win.db.y or 0) end
  f:SetMovable(not db.locked); f:SetResizable(not db.locked)
  if db.locked then win.grip:Hide() else win.grip:Show() end
  win.titleBar:SetHeight(db.rowHeight)
  if db.showTitle then win.titleBar:Show() else win.titleBar:Hide() end
  font(win.title.text, db.fontSize)
  setGlyph(win.lock, db.locked and "locked" or "unlocked")
  f:SetAlpha(Z.inFight and db.fightOpacity or db.idleOpacity)
  layoutRows(win)
end

function U.ApplySettings()
  for i = 1, getn(U.windows) do applyWindow(U.windows[i]) end
  dirty = true
  U.Refresh()
end

local function createWindow(index)
  local win = { index = index, db = windowSettings(index), rows = {}, rowBuf = {}, view = { level = 1, offset = 0 }, shown = true }
  local f = CreateFrame("Frame", "zDPSFrame"..(index > 1 and index or ""), UIParent)
  win.frame = f
  f.win = win
  f:SetFrameStrata("LOW")
  f:SetMinResize(90, 40)
  f:EnableMouse(true); f:EnableMouseWheel(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() if not Z.db.locked then this:StartMoving() end end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing(); savePosition(this.win) end)
  f:SetScript("OnMouseWheel", function()
    local w = this.win
    local n = w.rowBuf.n or 0
    if w.db.metric == "threat" then n = Z.Threat.rows.n or 0 end
    if arg1 > 0 then w.view.offset = max(w.view.offset - 1, 0) else w.view.offset = min(w.view.offset + 1, max(n - w.visible, 0)) end
    dirty = true; U.Refresh()
  end)
  f:SetScript("OnShow", function() this.win.shown = true; dirty = true; nextRefresh = 0; if U.IsThreatVisible() then Z.Threat.Start() end end)
  f:SetScript("OnHide", function() this.win.shown = false; if not U.IsThreatVisible() then Z.Threat.Stop() end; if menu then menu:Hide() end end)
  f:SetScript("OnSizeChanged", function() if this.win.shown and this.win.visible then layoutRows(this.win) end end)

  local bar = CreateFrame("Frame", nil, f)
  win.titleBar = bar
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND"); bar.bg:SetTexture(WHITE); bar.bg:SetAllPoints(bar)
  bar.bg:SetVertexColor(U.colors.title[1], U.colors.title[2], U.colors.title[3], 1)

  win.add = glyphButton(bar, "add", "New window", function() U.AddWindow() end)
  win.add:SetPoint("LEFT", bar, "LEFT", 1, 0)

  local title = CreateFrame("Button", nil, bar)
  win.title = title
  title.win = win
  title:SetPoint("TOPLEFT", bar, "TOPLEFT", 14, 0); title:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -52, 0)
  title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  title.text = title:CreateFontString(nil, "OVERLAY")
  title.text:SetPoint("LEFT", title, "LEFT", 2, 0); title.text:SetPoint("RIGHT", title, "RIGHT", 0, 0); title.text:SetJustifyH("LEFT")
  title:SetScript("OnClick", function()
    local w = this.win
    if w.view.level > 1 then U.Back(w); return end
    if arg1 == "RightButton" then openModeMenu(w) else openMetricMenu(w) end
  end)
  title:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(this.win.view.level > 1 and "Click: back" or "Left: metric  ·  Right: fight / report", .9, .9, .9); GameTooltip:Show()
  end)
  title:SetScript("OnLeave", function() GameTooltip:Hide() end)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() if not Z.db.locked then this.win.frame:StartMoving() end end)
  title:SetScript("OnDragStop", function() this.win.frame:StopMovingOrSizing(); savePosition(this.win) end)

  win.reset = glyphButton(bar, "reset", "Reset (shift: total only)", function()
    if IsShiftKeyDown() then D.ResetTotal() else D.ResetAll() end
    for i = 1, getn(U.windows) do U.windows[i].view.level = 1 end
    dirty = true; U.Refresh()
  end)
  win.reset:SetPoint("RIGHT", bar, "RIGHT", -39, 0)
  win.config = glyphButton(bar, "config", "Settings", function() Z.Config.Toggle() end)
  win.config:SetPoint("RIGHT", bar, "RIGHT", -26, 0)
  win.lock = glyphButton(bar, "unlocked", "Lock / unlock", function() Z.db.locked = not Z.db.locked; U.ApplySettings() end)
  win.lock:SetPoint("RIGHT", bar, "RIGHT", -13, 0)
  win.close = glyphButton(bar, "close", "Close window", function() U.CloseWindow(this:GetParent():GetParent().win) end)
  win.close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  win.close.win = win

  local grip = CreateFrame("Button", nil, f)
  win.grip = grip
  grip.win = win
  grip:SetWidth(9); grip:SetHeight(9)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  grip.tex = grip:CreateTexture(nil, "OVERLAY"); grip.tex:SetTexture(WHITE); grip.tex:SetAllPoints(grip)
  grip.tex:SetVertexColor(U.colors.border[1], U.colors.border[2], U.colors.border[3], .9)
  grip:SetScript("OnMouseDown", function() if not Z.db.locked then this.win.frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() this.win.frame:StopMovingOrSizing(); savePosition(this.win); layoutRows(this.win); dirty = true; U.Refresh() end)

  table.insert(U.windows, win)
  applyWindow(win)
  f:Show()
  return win
end

-- Picks a metric not already shown so a fresh window is immediately useful.
local function nextMetric()
  local used = {}
  for i = 1, getn(U.windows) do used[U.windows[i].db.metric] = true end
  for i = 1, getn(D.metrics) do if not used[D.metrics[i].key] then return D.metrics[i].key end end
  return "dps"
end

function U.AddWindow()
  local index = getn(U.windows) + 1
  local w = windowSettings(index)
  if not Z.db.windows[index].created then w.metric = nextMetric(); w.created = true end
  local win = createWindow(index)
  Z.db.windowCount = getn(U.windows)
  dirty = true; U.Refresh()
  return win
end

-- Closing removes a secondary window's settings; the first window only hides.
function U.CloseWindow(win)
  if not win then return end
  if win.index == 1 then win.frame:Hide(); return end
  win.frame:Hide()
  local idx = win.index
  table.remove(U.windows, idx)
  table.remove(Z.db.windows, idx)
  for i = idx, getn(U.windows) do
    local w = U.windows[i]
    w.index = i; w.db = Z.db.windows[i]
  end
  Z.db.windowCount = getn(U.windows)
  -- orphaned frames stay hidden; names are not reused within a session
end

function U.OnCombat(inFight)
  for i = 1, getn(U.windows) do
    local win = U.windows[i]
    win.frame:SetAlpha(inFight and Z.db.fightOpacity or Z.db.idleOpacity)
    if Z.db.hideOutOfCombat then if inFight then win.frame:Show() else win.frame:Hide() end end
  end
  dirty = true
end

function U.Show() for i = 1, getn(U.windows) do U.windows[i].frame:Show() end end
function U.Hide() for i = 1, getn(U.windows) do U.windows[i].frame:Hide() end end
function U.Toggle()
  local anyShown = false
  for i = 1, getn(U.windows) do if U.windows[i].frame:IsShown() then anyShown = true end end
  if anyShown then U.Hide() else U.Show() end
end

-- Introspection used by tests and other addons.
function U.Window(i) return U.windows[i or 1] end
function U.RowAt(i, w) local win = U.windows[w or 1]; local f = win and win.rows[i]; return f and f.row or nil end
function U.Title(w) local win = U.windows[w or 1]; return win and win.title.text:GetText() end
function U.ClickRow(i, button, w) local win = U.windows[w or 1]; local f = win and win.rows[i]; if f then this = f; arg1 = button or "LeftButton"; onRowClick() end end
function U.View(w) return U.windows[w or 1].view end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function()
  local now = GetTime()
  if now < nextRefresh then return end
  nextRefresh = now + .5
  if dirty or Z.inFight or U.IsThreatVisible() then U.Refresh() end
  if Z.Detail then Z.Detail.Tick() end
end)

function U.Init()
  Z.db.windows = Z.db.windows or {}
  local count = max(Z.db.windowCount or 1, 1)
  for i = 1, count do
    if not Z.db.windows[i] then windowSettings(i) end
    Z.db.windows[i].created = true
    createWindow(i)
  end
  Z.db.windowCount = count
  U.frame = U.windows[1].frame
  if U.IsThreatVisible() then Z.Threat.Start() end
  ticker:Show()
  dirty = true
  U.Refresh()
end
