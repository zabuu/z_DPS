-- zDPS: aggregation. Events are folded into the current fight and the running
-- total as they arrive; nothing is logged per event. Sub-tables are created on
-- first use and keep only the counters that were actually touched.
local Z = zDPS
local D = {}
Z.Data = D

local GetTime, getn, find, floor, max, min = GetTime, table.getn, string.find, math.floor, math.max, math.min
local Lists = Z.Lists

local current, total
D.history = {}

local function newSegment(kind)
  return { kind = kind, start = GetTime(), stop = nil, players = {}, count = 0, dmg = 0, heal = 0, combatTime = 0, target = nil }
end

total = newSegment("total")
D.total = total

function D.Duration(seg)
  if not seg then return 0 end
  if seg.kind == "total" then
    local live = 0
    if current and not current.stop then live = GetTime() - current.start end
    return max(seg.combatTime + live, 1)
  end
  return max((seg.stop or GetTime()) - seg.start, 1)
end

local function getPlayer(seg, name)
  local p = seg.players[name]
  if not p then
    p = { name = name, class = Z.ClassOf(name), dmg = 0, heal = 0, over = 0, taken = 0, dispel = 0, interrupt = 0,
          cc = 0, ccbreak = 0, deaths = 0, consum = 0, active = 0, last = 0 }
    seg.players[name] = p
    seg.count = seg.count + 1
  end
  return p
end

local function sub(p, field)
  local t = p[field]
  if not t then t = {}; p[field] = t end
  return t
end

local function rec(tbl, key)
  local r = tbl[key]
  if not r then r = { n = 0, v = 0 }; tbl[key] = r end
  return r
end

local function bump(r, field, by)
  r[field] = (r[field] or 0) + (by or 1)
end

-- Pet spell keys ("Cat: Claw") are built once per pet/spell pair.
local petKeys = {}
local function petKey(pet, sp)
  local t = petKeys[pet]
  if not t then t = {}; petKeys[pet] = t end
  local k = t[sp]
  if not k then k = pet..": "..sp; t[sp] = k end
  return k
end

-- Health deficits for overheal estimates (group units only).
local deficit = {}
function D.OnUnitHealth(unit)
  if not unit then return end
  local name = UnitName(unit)
  if name and Z.roster[name] then
    local maxHp = UnitHealthMax(unit)
    if maxHp and maxHp > 0 then deficit[name] = maxHp - UnitHealth(unit) end
  end
end
function D.OnRoster()
  for name in pairs(deficit) do if not Z.roster[name] then deficit[name] = nil end end
end

-- CC tracking: active CC aura per hostile target and who hit it last.
local ccActive, ccTime, lastHit, lastHitTime = {}, {}, {}, {}
local lastDispel = {} -- [owner] = last dispel spell cast, for DISPELFAILED lines
-- Consumables used shortly before a pull are credited to that pull.
local pending = {}   -- {name, spell, time} rows reused
local pendingN = 0
local lastBomb = {}  -- [owner][spell] = time, for multi-target explosives

-- Writers --------------------------------------------------------------------
local function addDamage(seg, owner, key, r, now)
  local p = getPlayer(seg, owner)
  local a = r.a
  p.dmg = p.dmg + a
  seg.dmg = seg.dmg + a
  if p.last > 0 and now - p.last <= 3.5 then p.active = p.active + (now - p.last) end
  p.last = now
  local s = rec(sub(p, "spells"), key)
  s.n = s.n + 1; s.v = s.v + a
  if r.crit then bump(s, "crit"); bump(s, "cv", a) end
  if r.periodic then bump(s, "tick") end
  if not s.min or a < s.min then s.min = a end
  if not s.max or a > s.max then s.max = a end
  if r.glance then bump(s, "glance") end
  if r.crush then bump(s, "crush") end
  if r.pabsorb then bump(s, "pabsorb", r.pabsorb) end
  if r.pblock then bump(s, "pblock", r.pblock) end
  if r.presist then bump(s, "presist", r.presist) end
  -- where it went: one number per target name
  if r.t then local tt = sub(p, "dmgTargets"); tt[r.t] = (tt[r.t] or 0) + a end
  if not seg.target and r.t and not Z.roster[r.t] then seg.target = r.t end
end

local function addTaken(seg, name, r)
  local p = getPlayer(seg, name)
  local a = r.a
  p.taken = p.taken + a
  local s = rec(sub(p, "takenSpells"), r.sp)
  s.n = s.n + 1; s.v = s.v + a
  if r.crit then bump(s, "crit"); bump(s, "cv", a) end
  if not s.min or a < s.min then s.min = a end
  if not s.max or a > s.max then s.max = a end
  if r.pabsorb then bump(s, "pabsorb", r.pabsorb) end
  if r.pblock then bump(s, "pblock", r.pblock) end
  if r.presist then bump(s, "presist", r.presist) end
end

local function addMiss(seg, owner, key, kind)
  local p = getPlayer(seg, owner)
  local s = rec(sub(p, "spells"), key)
  bump(s, kind)
end

local function addTakenMiss(seg, name, sp, kind)
  local p = getPlayer(seg, name)
  bump(rec(sub(p, "takenSpells"), sp), kind)
end

local function addHeal(seg, owner, sp, a, over, r)
  local p = getPlayer(seg, owner)
  p.heal = p.heal + a
  p.over = p.over + over
  seg.heal = seg.heal + a
  local s = rec(sub(p, "heals"), sp)
  s.n = s.n + 1; s.v = s.v + a
  if over > 0 then bump(s, "over", over) end
  if r.crit then bump(s, "crit") end
  if r.periodic then bump(s, "tick") end
  if not s.min or a < s.min then s.min = a end
  if not s.max or a > s.max then s.max = a end
  -- who it went to: amount and overheal per target name
  if r.t then local h = rec(sub(p, "healTargets"), r.t); h.n = h.n + 1; h.v = h.v + a; if over > 0 then bump(h, "over", over) end end
end

local function addCount(seg, owner, field, listField, key, by)
  local p = getPlayer(seg, owner)
  p[field] = max(p[field] + (by or 1), 0)
  if key then
    local t = sub(p, listField)
    t[key] = max((t[key] or 0) + (by or 1), 0)
  end
end

local function addConsumable(seg, name, sp)
  addCount(seg, name, "consum", "consumables", sp, 1)
end

local function useConsumable(name, sp, now)
  if Z.inFight and current then
    addConsumable(current, name, sp); addConsumable(total, name, sp)
  else
    addConsumable(total, name, sp)
    pendingN = pendingN + 1
    local row = pending[pendingN]
    if not row then row = {}; pending[pendingN] = row end
    row.name = name; row.sp = sp; row.time = now
  end
end

-- Dispatcher --------------------------------------------------------------------
local function src(name)
  if name then return Z.ResolveSource(name) end
  return nil
end

local function both(fn, a, b, c, d, e)
  if current and not current.stop then fn(current, a, b, c, d, e) end
  fn(total, a, b, c, d, e)
end

function D.Handle(kind, r)
  local now = GetTime()
  local s, t, sp = r.s, r.t, r.sp
  if kind == "dmg" then
    if not r.a then return end
    local owner, pet = src(s)
    local victim = src(t)
    if owner and owner ~= t then
      if not Z.inFight then Z.StartFight() end
      local key = pet and petKey(pet, sp) or sp
      both(addDamage, owner, key, r, now)
      if Lists.consumable[sp] == "Explosive" then
        local lb = lastBomb[owner]
        if not lb then lb = {}; lastBomb[owner] = lb end
        if not lb[sp] or now - lb[sp] > 0.6 then lb[sp] = now; useConsumable(owner, sp, now) end
      end
      if t and ccActive[t] and ccActive[t] ~= sp then lastHit[t] = owner; lastHitTime[t] = now end
    end
    if victim then
      if not Z.inFight and owner ~= victim then Z.StartFight() end
      if Z.inFight then both(addTaken, victim, r) end
    end
  elseif kind == "miss" then
    local owner, pet = src(s)
    if owner and Z.inFight then both(addMiss, owner, pet and petKey(pet, sp) or sp, r.k) end
    local victim = src(t)
    if victim and Z.inFight then both(addTakenMiss, victim, sp, r.k) end
  elseif kind == "heal" then
    if not r.a then return end
    local owner, pet = src(s)
    local a, over = r.a, 0
    local d = t and deficit[t]
    if d then
      local eff = min(a, d)
      over = a - eff
      deficit[t] = d - eff
    end
    if owner and Z.inFight then both(addHeal, owner, pet and petKey(pet, sp) or sp, a, over, r) end
    if t and Z.roster[t] and Lists.consumable[sp] == "Potion" then useConsumable(t, sp, now) end
  elseif kind == "aura" then
    if r.gone then
      if t and ccActive[t] == sp then
        local who = lastHit[t]
        if who and now - lastHitTime[t] < 1 and not r.dispelled then
          if Z.inFight then both(addCount, who, "ccbreak", "ccbreaks", sp, 1) end
        end
        ccActive[t] = nil; lastHit[t] = nil
      end
    elseif r.harm then
      if t and Lists.cc[sp] and not Z.roster[t] then ccActive[t] = sp; ccTime[t] = now; lastHit[t] = nil end
    else
      if t and Z.roster[t] and Lists.consumable[sp] then useConsumable(t, sp, now) end
    end
  elseif kind == "cast" then
    local owner = src(s)
    if owner and Z.inFight then
      if Lists.dispel[sp] then both(addCount, owner, "dispel", "dispels", sp, 1); lastDispel[owner] = sp
      elseif Lists.ccCast[sp] then both(addCount, owner, "cc", "ccs", sp, 1) end
    end
  elseif kind == "dispelfail" then
    local owner = src(s)
    if owner and Z.inFight then
      both(addCount, owner, "dispel", "dispels", lastDispel[owner], -1)
    end
  elseif kind == "interrupt" then
    local owner = src(s)
    if owner and Z.inFight then both(addCount, owner, "interrupt", "interrupts", sp, 1) end
  elseif kind == "power" then
    if t and Z.roster[t] and Lists.consumable[sp] == "Potion" then useConsumable(t, sp, now) end
  elseif kind == "death" then
    if t and Z.roster[t] and Z.inFight then both(addCount, t, "deaths", nil, nil, 1) end
  end
end

-- Fights ------------------------------------------------------------------------
function D.StartFight()
  current = newSegment("fight")
  D.current = current
  local now = GetTime()
  for i = 1, pendingN do
    local row = pending[i]
    if now - row.time <= 60 then addConsumable(current, row.name, row.sp) end
  end
  pendingN = 0
  for k in pairs(ccActive) do ccActive[k] = nil; lastHit[k] = nil end
  if Z.UI then Z.UI.Dirty() end
end

function D.EndFight()
  if not current or current.stop then return end
  current.stop = GetTime()
  total.combatTime = total.combatTime + (current.stop - current.start)
  table.insert(D.history, 1, current)
  while getn(D.history) > (Z.db.historySize or 5) do table.remove(D.history) end
  if Z.UI then Z.UI.Dirty() end
end

function D.ResetTotal()
  total = newSegment("total")
  D.total = total
  if Z.UI then Z.UI.Dirty() end
end

function D.ResetAll()
  D.ResetTotal()
  if current and not current.stop then
    current = newSegment("fight"); D.current = current
  else
    current = nil; D.current = nil
  end
  for i = getn(D.history), 1, -1 do D.history[i] = nil end
  for k in pairs(petKeys) do petKeys[k] = nil end
  for k in pairs(lastBomb) do lastBomb[k] = nil end
  pendingN = 0
end

function D.CountPlayers()
  local n = total.count
  for i = 1, getn(D.history) do n = n + D.history[i].count end
  return n
end

function D.Segment(mode)
  if mode == "total" then return total end
  if type(mode) == "number" then return D.history[mode] end
  return current
end

-- Metrics -------------------------------------------------------------------------
-- Rows are written into a caller-owned array: out[i] = {name, value, text, key}; out.n = count.
local function row(out, i, name, value, key, kind)
  local r = out[i]
  if not r then r = {}; out[i] = r end
  r.name = name; r.value = value; r.key = key; r.kind = kind; r.text = nil
  return r
end

local function byValue(a, b)
  if a.value == nil then return false end
  if b.value == nil then return true end
  return a.value > b.value
end
local function finish(out, n)
  for i = n + 1, getn(out) do out[i].value = nil; out[i].name = nil end
  out.n = n
  table.sort(out, byValue)
end

local function recordRows(p, field, out, valueField)
  local n = 0
  local t = p[field]
  if t then
    for key, r in pairs(t) do
      local v = valueField and (r[valueField] or 0) or r.v
      if v > 0 then n = n + 1; row(out, n, key, v, key, field) end
    end
  end
  finish(out, n)
end

-- Target rows: dmgTargets holds plain numbers; healTargets holds {v, over} (v includes overheal).
local function damageTargetRows(p, out)
  local n = 0
  local t = p.dmgTargets
  if t then for key, v in pairs(t) do if v > 0 then n = n + 1; row(out, n, key, v, key, "target") end end end
  finish(out, n)
end

local function healTargetRows(p, out, which)
  local n = 0
  local t = p.healTargets
  if t then
    for key, r in pairs(t) do
      local over = r.over or 0
      local v = which == "over" and over or (r.v - over)
      if v > 0 then n = n + 1; row(out, n, key, v, key, "target") end
    end
  end
  finish(out, n)
end

local function countRows(p, field, out)
  local n = 0
  local t = p[field]
  if t then for key, c in pairs(t) do if c > 0 then n = n + 1; row(out, n, key, c, key, field) end end end
  finish(out, n)
end

local function pct(a, b) if b > 0 then return a / b * 100 end return 0 end

-- Detail of one spell record (level 3). text is preformatted since these rows are few.
local MISS_FIELDS = { {"miss", "Missed"}, {"dodge", "Dodged"}, {"parry", "Parried"}, {"block", "Blocked"},
  {"resist", "Resisted"}, {"absorb", "Absorbed"}, {"immune", "Immune"}, {"evade", "Evaded"}, {"reflect", "Reflected"} }

local function fmtN(v) return Z.UI and Z.UI.FormatNumber(v) or tostring(floor(v)) end

local function damageDetail(r, out)
  local n = 0
  local attempts = r.n
  for i = 1, getn(MISS_FIELDS) do attempts = attempts + (r[MISS_FIELDS[i][1]] or 0) end
  local crit = r.crit or 0
  local normal = r.n - crit
  if normal > 0 then
    n = n + 1
    local rr = row(out, n, r.tick and "Ticks" or "Hits", normal)
    rr.text = string.format("%d  (%.0f%%)  avg %s", normal, pct(normal, attempts), fmtN((r.v - (r.cv or 0)) / normal))
  end
  if crit > 0 then
    n = n + 1
    local rr = row(out, n, "Crits", crit)
    rr.text = string.format("%d  (%.0f%%)  avg %s", crit, pct(crit, attempts), fmtN((r.cv or 0) / crit))
  end
  if r.glance then n = n + 1; row(out, n, "Glancing", r.glance).text = string.format("%d  (%.0f%%)", r.glance, pct(r.glance, attempts)) end
  if r.crush then n = n + 1; row(out, n, "Crushing", r.crush).text = string.format("%d  (%.0f%%)", r.crush, pct(r.crush, attempts)) end
  for i = 1, getn(MISS_FIELDS) do
    local f = MISS_FIELDS[i]
    local c = r[f[1]]
    if c and c > 0 then n = n + 1; row(out, n, f[2], c).text = string.format("%d  (%.0f%%)", c, pct(c, attempts)) end
  end
  if r.pabsorb then n = n + 1; row(out, n, "Partially absorbed", r.pabsorb).text = fmtN(r.pabsorb) end
  if r.pblock then n = n + 1; row(out, n, "Partially blocked", r.pblock).text = fmtN(r.pblock) end
  if r.presist then n = n + 1; row(out, n, "Partially resisted", r.presist).text = fmtN(r.presist) end
  if r.min then n = n + 1; row(out, n, "Min / max", r.max or r.min).text = fmtN(r.min).." / "..fmtN(r.max or r.min) end
  n = n + 1; row(out, n, "Total", r.v).text = string.format("%s  (%d)", fmtN(r.v), attempts)
  for i = n + 1, getn(out) do out[i].value = nil; out[i].name = nil end
  out.n = n
end

local function healDetail(r, out)
  local n = 0
  local crit = r.crit or 0
  local over = r.over or 0
  n = n + 1; row(out, n, r.tick and "Ticks" or "Heals", r.n).text = string.format("%d  avg %s", r.n, fmtN(r.v / max(r.n, 1)))
  if crit > 0 then n = n + 1; row(out, n, "Crits", crit).text = string.format("%d  (%.0f%%)", crit, pct(crit, r.n)) end
  n = n + 1; row(out, n, "Overheal", over).text = string.format("%s  (%.0f%%)", fmtN(over), pct(over, r.v))
  n = n + 1; row(out, n, "Effective", r.v - over).text = fmtN(r.v - over)
  if r.min then n = n + 1; row(out, n, "Min / max", r.max or r.min).text = fmtN(r.min).." / "..fmtN(r.max or r.min) end
  n = n + 1; row(out, n, "Total", r.v).text = fmtN(r.v)
  for i = n + 1, getn(out) do out[i].value = nil; out[i].name = nil end
  out.n = n
end

local function detailFor(p, field, key, out)
  local t = p[field]
  local r = t and t[key]
  if not r then out.n = 0; return end
  if field == "heals" then healDetail(r, out) else damageDetail(r, out) end
end

D.metrics = {
  { key = "dps", label = "DPS", rate = true, value = function(p, seg) return p.dmg / D.ActiveTime(p, seg) end, total = function(p) return p.dmg end,
    rows = function(p, seg, out) recordRows(p, "spells", out) end, detail = detailFor, field = "spells",
    targets = damageTargetRows, targetField = "dmgTargets" },
  { key = "damage", label = "Damage", value = function(p) return p.dmg end,
    perSecond = function(p, seg) return p.dmg / D.ActiveTime(p, seg) end,
    rows = function(p, seg, out) recordRows(p, "spells", out) end, detail = detailFor, field = "spells",
    targets = damageTargetRows, targetField = "dmgTargets" },
  { key = "hps", label = "HPS", rate = true, value = function(p, seg) return (p.heal - p.over) / D.ActiveTime(p, seg) end, total = function(p) return p.heal - p.over end,
    rows = function(p, seg, out) recordRows(p, "heals", out) end, detail = detailFor, field = "heals",
    targets = healTargetRows, targetField = "healTargets" },
  { key = "healing", label = "Healing", value = function(p) return p.heal - p.over end,
    perSecond = function(p, seg) return (p.heal - p.over) / D.ActiveTime(p, seg) end,
    rows = function(p, seg, out) recordRows(p, "heals", out) end, detail = detailFor, field = "heals",
    targets = healTargetRows, targetField = "healTargets" },
  { key = "overheal", label = "Overhealing", value = function(p) return p.over end,
    rows = function(p, seg, out) recordRows(p, "heals", out, "over") end, detail = detailFor, field = "heals",
    targets = function(p, out) healTargetRows(p, out, "over") end, targetField = "healTargets", targetOver = true },
  { key = "taken", label = "Damage taken", value = function(p) return p.taken end,
    rows = function(p, seg, out) recordRows(p, "takenSpells", out) end, detail = detailFor, field = "takenSpells" },
  { key = "dispels", label = "Dispels", count = true, value = function(p) return p.dispel end,
    rows = function(p, seg, out) countRows(p, "dispels", out) end },
  { key = "interrupts", label = "Interrupts", count = true, value = function(p) return p.interrupt end,
    rows = function(p, seg, out) countRows(p, "interrupts", out) end },
  { key = "cc", label = "CC used", count = true, value = function(p) return p.cc end,
    rows = function(p, seg, out) countRows(p, "ccs", out) end },
  { key = "ccbreaks", label = "CC breaks", count = true, value = function(p) return p.ccbreak end,
    rows = function(p, seg, out) countRows(p, "ccbreaks", out) end },
  { key = "deaths", label = "Deaths", count = true, value = function(p) return p.deaths end },
  { key = "consumables", label = "Consumables", count = true, value = function(p) return p.consum end,
    rows = function(p, seg, out) countRows(p, "consumables", out) end, category = function(key) return Lists.consumable[key] end },
  { key = "threat", label = "Threat", threat = true },
}
D.metricByKey = {}
for i = 1, getn(D.metrics) do D.metricByKey[D.metrics[i].key] = D.metrics[i] end

-- Player rows for a metric, sorted descending. Returns total of the metric.
function D.PlayerRows(seg, metric, out)
  local n, sum = 0, 0
  if seg then
    for name, p in pairs(seg.players) do
      local v = metric.value(p, seg)
      if v > 0 then
        n = n + 1
        local r = row(out, n, name, v, name, "player")
        r.class = p.class
        r.total = metric.total and metric.total(p) or nil
        r.perSecond = metric.perSecond and Z.db.showPerSecond and metric.perSecond(p, seg) or nil
        sum = sum + v
      end
    end
  end
  finish(out, n)
  return sum
end

function D.ActiveTime(p, seg)
  if Z.db.dpsTime == "active" then return max(p.active, 1) end
  return D.Duration(seg)
end
