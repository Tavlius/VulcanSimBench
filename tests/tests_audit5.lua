-- Regression tests for audit round 5: legacy tree totals, an honest talent-API
-- line, fresh-login advice, checksums of 2^31 and up, tree totals when ranks
-- misread, French quiver text, unloaded off-hand weapons.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end

-- 1. Only GetTalentTabInfo (no C_SpecializationInfo, no per-talent call): totals exported
for _, wrath in ipairs({ false, true }) do
  local F, h = export({ legacyTalents = true, forever = true, noTalentInfo = true, wrathTabInfo = wrath })
  local label = wrath and "(id, name, ..., points)" or "(name, icon, points)"
  check("legacy tab info " .. label .. ": totals", F.tal == "10-8-0", F.tal)
  check("legacy tab info " .. label .. ": names", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
  check("legacy tab info " .. label .. ": talentranks", (F.miss or ""):find("talentranks", 1, true), F.miss)
  check("legacy tab info " .. label .. ": no 'didn't answer'", not notes(h):find("didn't answer", 1, true), notes(h))
end

-- 2. /simx check names a talent API only if it really answers
do
  local h = H.boot({ forever = true })
  _G.C_SpecializationInfo.GetTalentInfo = function() return nil end
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("silent per-talent call: check says points per tree only", lines:find("(points per tree only)", 1, true), lines)
  local h2 = H.boot({ forever = true })
  _G.C_SpecializationInfo.GetTalentInfo = function() error("nope") end
  local lines2 = table.concat(h2.ns.CheckLines(), "\n")
  check("erroring per-talent call: check says points per tree only", lines2:find("(points per tree only)", 1, true), lines2)
  local F2 = h2.ns.Decode(h2.ns.Export())
  check("erroring per-talent call: export agrees", (F2.miss or ""):find("talentranks", 1, true) and F2.tal == "10-8-0", F2.miss)
  local lines3 = table.concat(H.boot().ns.CheckLines(), "\n")
  check("working API named", lines3:find("(C_SpecializationInfo)", 1, true), lines3)
  local lines4 = table.concat(H.boot({ legacyTalents = true }).ns.CheckLines(), "\n")
  check("legacy API named", lines4:find("(GetTalentInfo)", 1, true), lines4)
end

-- 3. Fresh login, nothing loaded: "export again" advice, in the addon and the string
do
  local cl = H.defaultClient()
  for _, it in pairs(cl.items) do it.uncached = true; it.stats = nil; it.tip = { { left = "Retrieving item information" } } end
  local F, h = export({ client = cl })
  check("nothing loaded: itemstats + notloaded", F.miss and F.miss:find("itemstats", 1, true) and F.miss:find("notloaded", 1, true), F.miss)
  check("nothing loaded: export-again advice", notes(h):find("Your items hadn't loaded yet", 1, true), notes(h))
  check("nothing loaded: no sheet-fallback wording from the addon", not notes(h):find("fall back to character-sheet", 1, true), notes(h))
  local F2, h2 = export({ noItemStats = true })
  check("item stats API missing (items loaded): no notloaded", not (F2.miss or ""):find("notloaded", 1, true), F2.miss)
  check("item stats API missing: sheet fallback wording", notes(h2):find("fall back to character-sheet", 1, true), notes(h2))
end

-- 4. Checksums at and above 2^31 (both halves formatted separately)
do
  local ns = H.boot().ns
  check("adler32 small", ns.Adler32(("x"):rep(5000)) == "14162848", ns.Adler32(("x"):rep(5000)))
  local all = {}
  for i = 0, 255 do all[#all + 1] = string.char(i) end
  local big = table.concat(all):rep(40)
  check("adler32 >= 2^31", ns.Adler32(big) == "f475ed1e", ns.Adler32(big))
  local body = "FSX1:cls=ROGUE;tn=" .. ("Z"):rep(3000)
  check("decode with a high checksum", ns.Decode(body .. "#" .. ns.Adler32(body)) ~= nil, ns.Adler32(body))
end

-- 5. Ranks unreadable but tree totals known: tal uses the totals
do
  local cl = H.defaultClient(); cl.secret = { rank = true }
  local F = export({ client = cl })
  check("secret ranks: tal from tree totals", F.tal == "10-8-0", F.tal)
  check("secret ranks: still flagged", (F.miss or ""):find("talents", 1, true), F.miss)
end

-- 6. French quiver: no-break space before %
do
  local ns = H.boot().ns
  check("quiver: NBSP before %", ns.ParseQuiver({ { left = "Carquois" }, { left = "Augmente la vitesse d'attaque à distance de 15\194\160%." } }) == 15)
  check("quiver: space before %", ns.ParseQuiver({ { left = "Carquois" }, { left = "15 %" } }) == 15)
end

-- 7. Unloaded off-hand of unknown type: reported, with wait advice
do
  local cl = H.defaultClient()
  cl.items[17] = { link = "|Hitem:777:0|h[Dagger]|h", uncached = true, stats = { ITEM_MOD_AGILITY_SHORT = 1 }, tip = { { left = "Retrieving item information" } } }
  local h = H.boot({ client = cl })
  local orig = h.c.instant
  h.c.instant = function(id) if id == 777 then return id end return orig(id) end
  local F = h.ns.Decode(h.ns.Export())
  check("unloaded unknown off-hand: weapon17 missing", (F.miss or ""):find("weapon17", 1, true), F.miss)
  check("unloaded unknown off-hand: wait advice", notes(h):find("(Off Hand) because it hadn't loaded yet", 1, true), notes(h))
end

H.finish("SimBench audit 5")
