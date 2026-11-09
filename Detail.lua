-- zDPS: per-player detail popup. Opens from a row click, shows summary tiles,
-- a share graph of the breakdown, the breakdown list and an outcome graph for
-- the selected entry. Built on first use; refreshed once a second while shown.
local Z = zDPS
local T = {}
Z.Detail = T

local D = Z.Data
local getn, floor, format, max, min = table.getn, math.floor, string.format, math.max, math.min
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local FONT = "Fonts\\ARIALN.TTF"
local W, H = 360, 262
local TITLE_H, TILE_H, SHARE_H, ROW_H = 15, 28, 7, 13
local LIST_W = 170

local frame, listRows, legendRows, shareSegs, outcomeSegs, tiles
listRows, legendRows, shareSegs, outcomeSegs, tiles = {}, {}, {}, {}, {}
local state = { player = nil, selected = nil, offset = 0, win = nil }
local rowBuf, detailBuf = {}, {}
local nextTick = 0

local PALETTE = {
  { .36, .62, .9 }, { .95, .73, .25 }, { .4, .78, .5 }, { .9, .45, .35 }, { .7, .5, .9 },
  { .3, .78, .78 }, { .9, .6, .8 }, { .75, .75, .45 }, { .55, .55, .62 },
}
local OUTCOME = {
  Hits = { .36, .62, .9 }, Ticks = { .36, .62, .9 }, Heals = { .35, .75, .45 }, Crits = { .95, .73, .25 },
  Missed = { .62, .62, .62 }, Dodged = { .85, .55, .25 }, Parried = { .85, .4, .4 }, Blocked = { .6, .5, .85 },
  Resisted = { .6, .35, .85 }, Absorbed = { .3, .72, .72 }, Immune = { .5, .5, .5 }, Evaded = { .45, .45, .45 },
  Reflected = { .35, .8, .45 }, Overheal = { .85, .35, .35 }, Effective = { .35, .75, .45 },
  Glancing = { .5, .6, .7 }, Crushing = { .9, .4, .2 },
}
local SEGMENTS = { { "n", "Hits" }, { "crit", "Crits" }, { "miss", "Missed" }, { "dodge", "Dodged" }, { "parry", "Parried" },
  { "block", "Blocked" }, { "resist", "Resisted" }, { "absorb", "Absorbed" }, { "immune", "Immune" }, { "evade", "Evaded" }, { "reflect", "Reflected" } }

local function font(fs, size, muted)
  if not fs:SetFont(FONT, size or 10, "") and fs.SetFontObject then fs:SetFontObject(GameFontHighlightSmall) end
  local c = muted and Z.UI.colors.muted or Z.UI.colors.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function tex(parent, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK"); t:SetTexture(WHITE); return t
end

local function panel(f, alpha)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  local bg, bd = Z.UI.colors.bg, Z.UI.colors.border
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or .96); f:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
end

local function fmt(v) return Z.UI.FormatNumber(v) end
local function fmtTime(sec) sec = floor(sec); return format("%d:%02d", floor(sec / 60), sec - floor(sec / 60) * 60) end

-- Build -------------------------------------------------------------------------------
local function tile(i, label)
  local t = CreateFrame("Frame", nil, frame)
  t:SetHeight(TILE_H)
  t.bg = tex(t, "BACKGROUND"); t.bg:SetAllPoints(t); t.bg:SetVertexColor(.08, .1, .13, 1)
  t.label = t:CreateFontString(nil, "OVERLAY"); t.label:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -3); font(t.label, 8, true); t.label:SetText(label)
  t.value = t:CreateFontString(nil, "OVERLAY"); t.value:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 4, 3); font(t.value, 12)
  tiles[i] = t
  return t
end

local function onListClick()
  if this.row then state.selected = this.row.key; T.Refresh() end
end

local function listRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, frame.list)
  r:SetHeight(ROW_H - 1)
  r:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
  r:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", -1, -1 - (i - 1) * ROW_H)
  r.bar = tex(r); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.dot = tex(r, "OVERLAY"); r.dot:SetWidth(5); r.dot:SetHeight(5); r.dot:SetPoint("LEFT", r, "LEFT", 3, 0)
  r.sel = tex(r, "BACKGROUND"); r.sel:SetAllPoints(r); r.sel:SetVertexColor(1, 1, 1, .08); r.sel:Hide()
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetPoint("LEFT", r, "LEFT", 11, 0); r.name:SetJustifyH("LEFT"); font(r.name, 10)
  r.value = r:CreateFontString(nil, "OVERLAY"); r.value:SetPoint("RIGHT", r, "RIGHT", -3, 0); r.value:SetJustifyH("RIGHT"); font(r.value, 10)
  r.name:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
  r:SetScript("OnClick", onListClick)
  listRows[i] = r
  return r
end

local function legendRow(i)
  local r = legendRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, frame.right)
  r:SetHeight(ROW_H - 1)
  r:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 3, -34 - (i - 1) * (ROW_H - 1))
  r:SetPoint("TOPRIGHT", frame.right, "TOPRIGHT", -3, -34 - (i - 1) * (ROW_H - 1))
  r.dot = tex(r, "OVERLAY"); r.dot:SetWidth(6); r.dot:SetHeight(6); r.dot:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.name = r:CreateFontString(nil, "OVERLAY"); r.name:SetPoint("LEFT", r, "LEFT", 9, 0); r.name:SetJustifyH("LEFT"); font(r.name, 9, true)
  r.value = r:CreateFontString(nil, "OVERLAY"); r.value:SetPoint("RIGHT", r, "RIGHT", 0, 0); r.value:SetJustifyH("RIGHT"); font(r.value, 9)
  r.name:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
  legendRows[i] = r
  return r
end

local function segTex(pool, parent, i)
  local s = pool[i]
  if s then return s end
  s = tex(parent); s:SetPoint("TOP", parent, "TOP", 0, 0); s:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
  pool[i] = s
  return s
end

-- Lays out horizontal stacked segments from an array of {value, color} written into segs[i].v/.c.
local function layoutSegments(pool, parent, count, total, bar)
  local x, width = 0, bar:GetWidth()
  for i = 1, count do
    local s = segTex(pool, parent, i)
    local v = pool[i].v or 0
    local w = total > 0 and floor(v / total * width + .5) or 0
    if i == count then w = max(width - x, 0) end
    if w > 0 then
      s:ClearAllPoints(); s:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0); s:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
      s:SetWidth(w); local c = pool[i].c; s:SetVertexColor(c[1], c[2], c[3], .95); s:Show()
      x = x + w
    else s:Hide() end
  end
  for i = count + 1, getn(pool) do pool[i]:Hide() end
end

local function build()
  frame = CreateFrame("Frame", "zDPSDetail", UIParent)
  T.frame = frame
  frame:SetWidth(W); frame:SetHeight(H)
  frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:EnableMouseWheel(true); frame:SetMovable(true)
  frame:SetClampedToScreen(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); Z.db.detailX = frame:GetLeft(); Z.db.detailY = frame:GetTop() end)
  frame:SetScript("OnMouseWheel", function()
    local n = rowBuf.n or 0
    if arg1 > 0 then state.offset = max(state.offset - 1, 0) else state.offset = min(state.offset + 1, max(n - T.visible, 0)) end
    T.Refresh()
  end)
  panel(frame)
  if Z.db.detailX and Z.db.detailY then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Z.db.detailX, Z.db.detailY)
  else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
  table.insert(UISpecialFrames, "zDPSDetail")

  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1); bar:SetHeight(TITLE_H)
  bar.bg = tex(bar, "BACKGROUND"); bar.bg:SetAllPoints(bar); local tc = Z.UI.colors.title; bar.bg:SetVertexColor(tc[1], tc[2], tc[3], 1)
  frame.icon = tex(bar, "OVERLAY"); frame.icon:SetWidth(TITLE_H - 3); frame.icon:SetHeight(TITLE_H - 3); frame.icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
  frame.title = bar:CreateFontString(nil, "OVERLAY"); frame.title:SetPoint("LEFT", bar, "LEFT", TITLE_H + 2, 0); font(frame.title, 11)
  frame.sub = bar:CreateFontString(nil, "OVERLAY"); frame.sub:SetPoint("RIGHT", bar, "RIGHT", -16, 0); font(frame.sub, 9, true)
  local close = CreateFrame("Button", nil, bar); close:SetWidth(12); close:SetHeight(12); close:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
  close.text = close:CreateFontString(nil, "OVERLAY"); close.text:SetPoint("CENTER", close, "CENTER", 0, 0); font(close.text, 10, true); close.text:SetText("x")
  close:SetScript("OnClick", function() frame:Hide() end)

  local tileW = floor((W - 2 - 3 * 2) / 4)
  for i, label in ipairs({ "Total", "Per second", "Share", "Active" }) do
    local t = tile(i, label)
    t:SetWidth(tileW)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", 1 + (i - 1) * (tileW + 2), -TITLE_H - 3)
  end

  frame.share = CreateFrame("Frame", nil, frame)
  frame.share:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -TITLE_H - TILE_H - 6); frame.share:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -TITLE_H - TILE_H - 6)
  frame.share:SetHeight(SHARE_H)
  frame.share.bg = tex(frame.share, "BACKGROUND"); frame.share.bg:SetAllPoints(frame.share); frame.share.bg:SetVertexColor(.08, .1, .13, 1)

  local bodyTop = -TITLE_H - TILE_H - SHARE_H - 9
  frame.list = CreateFrame("Frame", nil, frame)
  frame.list:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, bodyTop); frame.list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
  frame.list:SetWidth(LIST_W)
  frame.right = CreateFrame("Frame", nil, frame)
  frame.right:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 2, 0); frame.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  frame.right.bg = tex(frame.right, "BACKGROUND"); frame.right.bg:SetAllPoints(frame.right); frame.right.bg:SetVertexColor(.06, .075, .1, 1)
  frame.right.title = frame.right:CreateFontString(nil, "OVERLAY"); frame.right.title:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 3, -4)
  frame.right.title:SetPoint("TOPRIGHT", frame.right, "TOPRIGHT", -3, -4); frame.right.title:SetJustifyH("LEFT"); font(frame.right.title, 10)
  frame.outcome = CreateFrame("Frame", nil, frame.right)
  frame.outcome:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 3, -18); frame.outcome:SetPoint("TOPRIGHT", frame.right, "TOPRIGHT", -3, -18)
  frame.outcome:SetHeight(9)
  frame.outcome.bg = tex(frame.outcome, "BACKGROUND"); frame.outcome.bg:SetAllPoints(frame.outcome); frame.outcome.bg:SetVertexColor(.08, .1, .13, 1)
  frame.empty = frame.right:CreateFontString(nil, "OVERLAY"); frame.empty:SetPoint("TOPLEFT", frame.right, "TOPLEFT", 3, -20); font(frame.empty, 9, true)

  T.visible = floor((H + bodyTop - 2) / ROW_H)
  for i = 1, T.visible do listRow(i) end
  frame:Hide()
end

-- Refresh -----------------------------------------------------------------------------
local function paintList(metric, p, seg)
  local sum = 0
  for i = 1, rowBuf.n do sum = sum + (rowBuf[i].value or 0) end
  if state.offset > max(rowBuf.n - T.visible, 0) then state.offset = max(rowBuf.n - T.visible, 0) end
  local maxValue = rowBuf.n > 0 and rowBuf[1].value or 0
  -- share graph: top entries by colour, remainder grey
  local shown = min(rowBuf.n, getn(PALETTE) - 1)
  local rest = 0
  for i = shown + 1, rowBuf.n do rest = rest + rowBuf[i].value end
  for i = 1, shown do local s = segTex(shareSegs, frame.share, i); s.v = rowBuf[i].value; s.c = PALETTE[i] end
  local count = shown
  if rest > 0 then count = count + 1; local s = segTex(shareSegs, frame.share, count); s.v = rest; s.c = PALETTE[getn(PALETTE)] end
  layoutSegments(shareSegs, frame.share, count, sum, frame.share)
  local selectedFound = false
  for i = 1, T.visible do
    local f = listRows[i]
    local idx = i + state.offset
    local r = rowBuf[idx]
    if r and r.value then
      f.row = r
      local c = PALETTE[min(idx, getn(PALETTE))]
      f.dot:SetVertexColor(c[1], c[2], c[3], 1)
      f.bar:SetVertexColor(c[1], c[2], c[3], .28)
      f.bar:SetWidth(max(maxValue > 0 and r.value / maxValue * (LIST_W - 2) or 0, 1))
      f.name:SetText(r.name)
      if metric.count then
        local cat = metric.category and metric.category(r.key)
        f.value:SetText(cat and format("%d  %s", r.value, cat) or format("%d", r.value))
      else f.value:SetText(format("%s  %.0f%%", fmt(r.value), sum > 0 and r.value / sum * 100 or 0)) end
      if r.key == state.selected then f.sel:Show(); selectedFound = true else f.sel:Hide() end
      f:Show()
    else f.row = nil; f:Hide() end
  end
  if not selectedFound and rowBuf.n > 0 and not (state.selected and p[metric.field or ""] and p[metric.field or ""][state.selected]) then
    state.selected = rowBuf[1].key
    if listRows[1].row then listRows[1].sel:Show() end
  end
end

local function paintOutcome(metric, p)
  local right = frame.right
  local rec = metric.field and p[metric.field] and state.selected and p[metric.field][state.selected]
  if not rec then
    right.title:SetText(state.selected or "")
    frame.outcome:Hide(); frame.empty:Show()
    frame.empty:SetText(metric.count and "counts only" or "select an entry")
    for i = 1, getn(legendRows) do legendRows[i]:Hide() end
    return
  end
  frame.empty:Hide(); frame.outcome:Show()
  right.title:SetText(state.selected)
  local count, total = 0, 0
  if metric.field == "heals" then
    local over = rec.over or 0
    count = 2
    local s = segTex(outcomeSegs, frame.outcome, 1); s.v = rec.v - over; s.c = OUTCOME.Effective
    s = segTex(outcomeSegs, frame.outcome, 2); s.v = over; s.c = OUTCOME.Overheal
    total = rec.v
  else
    for i = 1, getn(SEGMENTS) do
      local field, label = SEGMENTS[i][1], SEGMENTS[i][2]
      local v = rec[field] or 0
      if field == "n" then v = v - (rec.crit or 0) end
      if v > 0 then count = count + 1; local s = segTex(outcomeSegs, frame.outcome, count); s.v = v; s.c = OUTCOME[label]; total = total + v end
    end
  end
  layoutSegments(outcomeSegs, frame.outcome, count, total, frame.outcome)
  metric.detail(p, metric.field, state.selected, detailBuf)
  for i = 1, detailBuf.n do
    local r = detailBuf[i]
    local f = legendRow(i)
    local c = OUTCOME[r.name]
    if c then f.dot:SetVertexColor(c[1], c[2], c[3], 1); f.dot:Show() else f.dot:Hide() end
    f.name:SetText(r.name); f.value:SetText(r.text or fmt(r.value)); f:Show()
  end
  for i = detailBuf.n + 1, getn(legendRows) do legendRows[i]:Hide() end
end

function T.Refresh()
  if not frame or not frame:IsShown() or not state.player then return end
  local win = state.win or Z.UI.Window(1)
  local metric = Z.UI.Metric(win)
  local seg = Z.UI.Segment(win)
  local p = seg and seg.players[state.player]
  if metric.threat or not p then frame:Hide(); return end
  if Z.db.classIcons and Z.UI.SetClassIcon(frame.icon, p.class) then frame.icon:Show(); frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 3, 0)
  else frame.icon:Hide(); frame.title:SetPoint("LEFT", frame.icon, "LEFT", 0, 0) end
  frame.title:SetText(state.player.."  ·  "..metric.label)
  local mode = win.db.mode == "total" and "Total" or (seg.target or "Current")
  frame.sub:SetText(format("%s  %s", mode, fmtTime(D.Duration(seg))))
  -- tiles
  local value = metric.value(p, seg)
  local totalValue = metric.total and metric.total(p) or value
  local groupSum = 0
  for _, other in pairs(seg.players) do groupSum = groupSum + metric.value(other, seg) end
  tiles[1].value:SetText(metric.count and format("%d", totalValue) or fmt(totalValue))
  tiles[2].value:SetText(metric.count and "-" or fmt((metric.rate and value) or (totalValue / D.Duration(seg))))
  tiles[3].value:SetText(format("%.0f%%", groupSum > 0 and value / groupSum * 100 or 0))
  tiles[4].value:SetText(format("%.0f%%", min(p.active / D.Duration(seg) * 100, 100)))
  if metric.rows then metric.rows(p, seg, rowBuf) else rowBuf.n = 0 end
  paintList(metric, p, seg)
  paintOutcome(metric, p)
end

function T.Open(name, win)
  if not frame then build() end
  if state.player ~= name then state.selected = nil; state.offset = 0 end
  state.player = name
  state.win = win or Z.UI.Window(1)
  frame:Show()
  nextTick = 0
  T.Refresh()
end

function T.Tick(force)
  if not frame or not frame:IsShown() then return end
  local now = GetTime()
  if not force and now < nextTick then return end
  nextTick = now + 1
  T.Refresh()
end

function T.Close() if frame then frame:Hide() end end

-- Test hooks.
function T.Tiles() return tiles end
function T.ListRows() return listRows end
function T.LegendRows() return legendRows end
