-- Regression tests for audit round 4: Forever's talent API (no GetNumTalentTabs or
-- GetNumTalents; GetSpecializationInfo returning values or a table; maybe no
-- per-talent call at all), item-read messages, note sizing.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end

-- 1. Forever: trees and talents counted by asking
do
  local F = export({ forever = true })
  check("forever: points", F.tal == "10-8-0", F.tal)
  check("forever: ranks sorted", F.tr == "5032-53-0", F.tr)
  check("forever: names", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
  check("forever: nothing missing", F.miss == nil, F.miss)
  local T = export({ forever = true, specTable = true })
  check("forever, table return: same", T.tal == F.tal and T.tr == F.tr and T.tn == F.tn, tostring(T.tal) .. " " .. tostring(T.tn))
  local Q = export({ forever = true, specQuery = true })
  check("forever, query-table argument: same", Q.tal == F.tal and Q.tn == F.tn, tostring(Q.tal) .. " " .. tostring(Q.tn))
end

-- 2. Forever with no per-talent call: tree totals still exported
do
  local F, h = export({ forever = true, noTalentInfo = true })
  check("points only: tal from tree totals", F.tal == "10-8-0", F.tal)
  check("points only: names kept", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
  check("points only: no tr", F.tr == nil, F.tr)
  check("points only: flagged talentranks", (F.miss or ""):find("talentranks", 1, true)
    and not (F.miss or ""):find("talents,", 1, true), F.miss)
  check("points only: plain note with totals", notes(h):find("(10/8/0) but not each talent", 1, true), notes(h))
  check("points only: no talent-window advice", not notes(h):find("talent window", 1, true), notes(h))
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("check: says points per tree only", lines:find("Talent API: |cff33ff33yes|r (points per tree only)", 1, true), lines)
  check("check: tree totals listed", lines:find("Talents: Beast Mastery 10 / Marksmanship 8 / Survival 0", 1, true), lines)
  local T = export({ forever = true, noTalentInfo = true, specTable = true })
  check("points only, table return", T.tal == "10-8-0", T.tal)
end

-- 3. No talent API at all
do
  local F, h = export({ noTalents = true })
  check("no talent API: talents missing", (F.miss or ""):find("talents", 1, true) and F.tal == nil, F.miss)
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("check: talent API no", lines:find("Talent API: |cffff5555no|r", 1, true), lines)
end

-- 4. Debug dump works without GetNumTalentTabs
do
  local h = H.boot({ forever = true, specTable = true })
  H.slash("debug")
  local text = h.ns.CopyFrame().text
  check("debug: trees listed without GetNumTalentTabs", text:find("C_SpecializationInfo.GetSpecializationInfo(1)", 1, true), text)
  check("debug: table return shown", text:find('(a table: name "Beast Mastery", pointsSpent 10)', 1, true), text)
  check("debug: missing functions reported", text:find("GetNumTalentTabs: (no such API)", 1, true), text)
end

-- 5. Tree counting stops at the first silent tree, and never runs away
do
  local cl = H.defaultClient()
  for i = 4, 8 do cl.talents[i] = { name = "Extra" .. i, list = { { 1, 1, 0 } } } end
  local F = export({ client = cl, forever = true })
  local n = select(2, F.tal:gsub("-", "")) + 1
  check("tree count capped at 5", n == 5, F.tal)
end

-- 6. Item stats: loaded-but-unreadable vs not loaded; shirt and tabard don't count as "read"
do
  local cl = H.defaultClient()
  cl.items[1].stats = nil
  cl.items[1].tip = { { left = "Helm" }, { left = "300 Armor" }, { left = "+20 Agility" } }
  local _, h = export({ client = cl })
  check("loaded but unreadable: debug advice, not 'hadn't loaded'", notes(h):find("Couldn't read the stats of some items (Head)", 1, true)
    and not notes(h):find("hadn't loaded yet (Head)", 1, true), notes(h))
  local cl2 = H.defaultClient()
  for _, slot in ipairs({ 1, 16, 18 }) do cl2.items[slot].stats = nil; cl2.items[slot].uncached = true end
  cl2.items[4] = { link = "|Hitem:45:0|h[Shirt]|h", stats = {} }
  local F2 = export({ client = cl2 })
  check("only a shirt readable: whole-gear itemstats", F2.miss and (("," .. F2.miss .. ","):find(",itemstats,", 1, true)), F2.miss)
end

-- 7. Notes size to their text when the client can measure it
do
  local h = H.boot()
  h.ns.ShowCopy("x", { "short" })
  local small = h.ns.CopyFrame().height
  local long = ("A long note that wraps over several lines in the copy box. "):rep(4)
  h.ns.ShowCopy("x", { long, long })
  local big = h.ns.CopyFrame().height
  check("one short note: two-line minimum", small == 140 + 26, small)
  check("long notes: box grows past two lines each", big > 140 + 2 * 26, big)
end

H.finish("SimBench audit 4")
