-- SimBench: the export string.
--
--   FSX1:key=value;key=value;...#adler32
--
-- One line of plain ASCII, so it survives Discord, forums and chat windows.
-- Lists use "," and sub-fields ":". The checksum covers everything before "#"
-- so a string cut short while copying is caught, not silently mis-read.
-- The full field list is in README.md; simx-decode.js reads it in the sim.
local _, ns = ...

-- Field order in the string (stable so two exports diff cleanly).
ns.FIELD_ORDER = { "v", "b", "d", "cls", "race", "fac", "lvl", "tal", "tr", "tn",
  "g", "w", "ammo", "qv", "set", "sb", "sbx", "is", "ie", "sh", "bs", "au", "miss" }

-- Sheet and base-stat keys, in order.
ns.SHEET_KEYS = { "str", "agi", "sta", "int", "spi", "ap", "rap", "crit", "rcrit", "scrit",
  "hit", "shit", "sp", "heal", "armor" }
ns.BASE_KEYS = { "str", "agi", "sta", "int", "spi", "ap", "rap" }

local function joinMap(map, keys, places)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = ns.fmt(map[k], places)
    if v then parts[#parts + 1] = k .. ":" .. v end
  end
  return #parts > 0 and table.concat(parts, ",") or nil
end

local sortedKeys = ns.SortedKeys

-- data (from ns.Collect) -> field table of strings.
function ns.Fields(data)
  local F = {}
  F.v = ns.VERSION
  F.b = ns.clean(data.build)
  F.d = ns.clean(data.date)
  F.cls = ns.clean(data.class)
  F.race = ns.clean(data.race)
  F.fac = ns.clean(data.faction)
  F.lvl = ns.fmt(data.level, 0)
  local T = data.talents
  if T then
    local pts, ranks, names = {}, {}, {}
    for i, tab in ipairs(T) do
      pts[i] = ns.fmt(tab.points, 0) or "0"
      ranks[i] = tab.ranks or ""
      names[i] = ns.clean(tab.name) or ""
    end
    if #pts > 0 then
      F.tal = table.concat(pts, "-")
      -- No ranks at all (a client that only gives points per tree): no tr.
      if table.concat(ranks) ~= "" then F.tr = table.concat(ranks, "-") end
      F.tn = table.concat(names, ",")
    end
  end
  if data.gear and #data.gear > 0 then
    local parts = {}
    for _, it in ipairs(data.gear) do
      parts[#parts + 1] = it.slot .. ":" .. it.id .. ":" .. (it.ench or 0) .. (it.loc and (":" .. it.loc) or "")
    end
    F.g = table.concat(parts, ",")
  end
  if data.weapons then
    local parts = {}
    for _, slot in ipairs({ 16, 17, 18 }) do
      local w = data.weapons[slot]
      if w and ns.fmt(w.min) and ns.fmt(w.max) and ns.fmt(w.speed) then
        parts[#parts + 1] = slot .. ":" .. ns.fmt(w.min) .. ":" .. ns.fmt(w.max) .. ":" .. ns.fmt(w.speed)
          .. (w.loc and (":" .. w.loc) or "")
      end
    end
    if #parts > 0 then F.w = table.concat(parts, ",") end
  end
  F.ammo = ns.fmt(data.ammoDps, 1)
  if data.sets and next(data.sets) then
    local ids = {}
    for id in pairs(data.sets) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = id .. ":" .. data.sets[id] end
    F.set = table.concat(parts, ",")
  end
  F.qv = ns.fmt(data.quiverHaste, 1)
  -- Active set bonuses: plain stats summed (sb), everything else by set:bonus number (sbx).
  if data.setBonus and next(data.setBonus) then F.sb = joinMap(data.setBonus, sortedKeys(data.setBonus), 2) end
  if data.setOther and #data.setOther > 0 then
    local parts = {}
    for i, o in ipairs(data.setOther) do parts[i] = o.set .. ":" .. o.idx end
    F.sbx = table.concat(parts, ",")
  end
  if data.itemStats then F["is"] = joinMap(data.itemStats, sortedKeys(data.itemStats), 2) end
  -- The part of "is" read from "Equip:" text because GetItemStats left it out.
  if data.equipFill and next(data.equipFill) then F.ie = joinMap(data.equipFill, sortedKeys(data.equipFill), 2) end
  if data.sheet then F.sh = joinMap(data.sheet, ns.SHEET_KEYS, 2) end
  if data.base then F.bs = joinMap(data.base, ns.BASE_KEYS, 0) end
  if data.auras and #data.auras > 0 then
    local ids = {}
    for i, id in ipairs(data.auras) do ids[i] = ns.fmt(id, 0) end
    F.au = table.concat(ids, ",")
  end
  if data.missing and #data.missing > 0 then
    local m = {}
    for i, k in ipairs(data.missing) do m[i] = ns.clean(k) end
    F.miss = table.concat(m, ",")
  end
  return F
end

function ns.Encode(data)
  local F = ns.Fields(data)
  local parts = {}
  for _, k in ipairs(ns.FIELD_ORDER) do
    if F[k] and F[k] ~= "" then parts[#parts + 1] = k .. "=" .. F[k] end
  end
  local body = ns.FORMAT .. ":" .. table.concat(parts, ";")
  return body .. "#" .. ns.Adler32(body)
end

-- string -> fields table, or nil + reason. Used by /simx verify and the tests;
-- simx-decode.js is the sim-side twin and finds the string the same way: the
-- first "FSX<n>:" ... "#<8 hex>" pair whose checksum matches, so text pasted
-- around it (or the string pasted twice) doesn't matter. One pass per start
-- (running checksum), at most MAX_HEADS starts and MAX_PASTE bytes, so even a
-- huge or hostile paste can't freeze the game.
local MAX_HEADS, MAX_PASTE = 8, 65536
local HEX = "^%x%x%x%x%x%x%x%x"

-- From s's position a: the end of the first body whose Adler-32 matches the
-- 8 hex digits after a following "#", or nil.
local function verifiedEnd(s, a)
  local A, B = 1, 0
  for i = a, #s do
    local c = s:byte(i)
    if c == 35 then   -- "#": does the checksum of s[a..i-1] follow?
      local hex = s:sub(i + 1, i + 8)
      if hex:find(HEX) and string.format("%04x%04x", B, A) == hex:lower() then return i - 1 end
    end
    A = (A + c) % 65521
    B = (B + A) % 65521
  end
  return nil
end

function ns.Decode(s)
  s = ns.str(s)
  if not s then return nil, "not a string" end
  if #s > MAX_PASTE * 2 then return nil, "too long to be a SimBench string" end
  -- Copying can wrap lines or add spaces (Unicode ones included).
  for _, u in ipairs(ns.UNICODE_SPACES) do s = s:gsub(u, "") end
  for _, u in ipairs(ns.ZERO_WIDTH) do s = s:gsub(u, "") end
  s = s:gsub("%s+", "")
  if #s > MAX_PASTE then return nil, "too long to be a SimBench string" end
  local why, other = "not a SimBench string", nil
  local start, heads = 1, 0
  while heads < MAX_HEADS do
    local a, b, fmt = s:find("(FSX%d+):", start)
    if not a then break end
    heads = heads + 1
    local e = verifiedEnd(s, a)
    if e then
      if fmt == ns.FORMAT then
        local F = {}
        for pair in s:sub(b + 1, e):gmatch("[^;]+") do
          local k, v = pair:match("^(%w+)=(.*)$")
          if k then F[k] = v end
        end
        return F
      end
      -- A complete string in another format: keep looking for one we read.
      other = other or fmt
    elseif why == "not a SimBench string" then
      why = s:find("#%x%x%x%x%x%x%x%x", b) and "checksum mismatch (string changed or cut off)" or "no checksum (string cut off?)"
    end
    start = a + 1
  end
  if other then
    local mine, theirs = tonumber(ns.FORMAT:match("%d+")), tonumber(other:match("%d+"))
    return nil, "format " .. other .. (theirs > mine and " is newer than this addon reads; update SimBench"
      or " is from an older SimBench; export again")
  end
  return nil, why
end
