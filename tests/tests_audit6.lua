-- Regression tests for audit round 6: "(N) Set:" active bonuses, talent API
-- fallbacks, no-talent message, empty stats tables, shirt-only characters,
-- 0-0 weapons, Equip lines that aren't stats.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end
local function modernSet(cl, have)
  local tip = { { left = "Helm" }, { left = "Giantstalker Armor (" .. have .. "/8)" }, { left = "" },
    { left = "(3) Set: +40 Attack Power." }, { left = "(5) Set: Improves your chance to hit by 1%." },
    { left = "(8) Set: Increases the damage of Multi-Shot by 15%." } }
  for i, slot in ipairs({ 1, 5, 7, 3, 10, 6, 8, 9 }) do
    if i <= have then cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = { ITEM_MOD_AGILITY_SHORT = 1 }, tip = tip } end
  end
end

-- 1. Modern-style "(N) Set:" lines: active when N pieces are worn
do
  local cl = H.defaultClient(); modernSet(cl, 3)
  local F = export({ client = cl })
  check("(3) Set at 3/8: active", F.sb == "AP:40", F.sb)
  check("(5)/(8) Set at 3/8: inactive", F.sbx == nil and not (F.sb or ""):find("HIT", 1, true), tostring(F.sbx))
  local cl2 = H.defaultClient(); modernSet(cl2, 2)
  local F2 = export({ client = cl2 })
  check("(3) Set at 2/8: inactive", F2.sb == nil, F2.sb)
  local cl8 = H.defaultClient(); modernSet(cl8, 8)
  local F8 = export({ client = cl8 })
  check("8/8: all active", F8.sb == "AP:40,HIT:1" and F8.sbx == "515:3", tostring(F8.sb) .. " " .. tostring(F8.sbx))
  local ns = H.boot().ns
  _G.ITEM_SET_BONUS_GRAY = "Set (%2$d): %1$s"   -- a locale with the number after the text
  local s = ns.ParseSetTooltip({ { left = "x" }, { left = "Y (3/5)" }, { left = "Set (3): +10 Agility." }, { left = "Set (5): +5 Stamina." } })
  check("reordered placeholders: number found", s and s.bonuses[1].active and not s.bonuses[2].active and s.bonuses[1].text == "+10 Agility.",
    s and s.bonuses[1] and s.bonuses[1].text)
end

-- 2. Talent API fallbacks
do
  local h = H.boot({ alsoLegacy = true })
  _G.C_SpecializationInfo.GetTalentInfo = function(q) return { row = 1, col = 1, points = 0 } end   -- other field names
  local F = h.ns.Decode(h.ns.Export())
  check("odd table fields: old GetTalentInfo used", F.tr == "5032-53-0" and F.miss == nil, tostring(F.tr) .. " " .. tostring(F.miss))
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("check names the API that answered", lines:find("(GetTalentInfo)", 1, true), lines)
  local h2 = H.boot({ alsoLegacy = true, forever = true, noTalentInfo = true })
  local orig = _G.C_SpecializationInfo.GetSpecializationInfo
  _G.C_SpecializationInfo.GetSpecializationInfo = function(t) local r = { orig(t) }; r[7] = nil; return unpack(r, 1, 10) end
  _G.GetTalentInfo = nil
  local F2 = h2.ns.Decode(h2.ns.Export())
  check("points missing from new API: taken from GetTalentTabInfo", F2.tal == "10-8-0" and (F2.miss or ""):find("talentranks", 1, true), tostring(F2.tal) .. " " .. tostring(F2.miss))
end

-- 3. No talent API: a message that matches (nothing to check)
do
  local _, h = export({ noTalents = true })
  check("no talent API: 'pick them in the sim'", notes(h):find("Couldn't find your talents", 1, true)
    and not notes(h):find("open your talent window", 1, true), notes(h))
end

-- 4. Empty stats table for a loaded item whose tooltip shows stats: unread, not zero
do
  local cl = H.defaultClient(); cl.items[1].stats = {}
  cl.items[1].tip = { { left = "Helm" }, { left = "300 Armor" }, { left = "+20 Agility" } }
  local F = export({ client = cl })
  check("empty table but tooltip stats: flagged", (F.miss or ""):find("itemstats1", 1, true), F.miss)
  local cl2 = H.defaultClient(); cl2.items[13] = { link = "|Hitem:13:0|h[Trinket]|h", stats = {}, tip = { { left = "Trinket" }, { left = "Use: Restores 100 mana." } } }
  local F2 = export({ client = cl2 })
  check("empty table, plain trinket: fine", not (F2.miss or ""):find("itemstats13", 1, true), F2.miss)
end

-- 5. Shirt or tabard only: not "item stats unreadable"
do
  local cl = H.defaultClient(); cl.items = { [4] = { link = "|Hitem:45:0|h[Shirt]|h", stats = nil } }; cl.ammo = nil
  local F = export({ client = cl })
  check("shirt only: no itemstats flag", not (F.miss or ""):find("itemstats", 1, true), F.miss)
end

-- 6. A "0 - 0" damage line isn't a weapon (the sim would drop it anyway)
do
  local ns = H.boot().ns
  check("0-0 weapon rejected", ns.ParseWeapon({ { left = "x" }, { left = "0 - 0 Damage", right = "Speed 2.00" } }) == nil)
end

-- 7. Equip lines that aren't stats: counted in /simx check
do
  local cl = H.defaultClient()
  cl.items[1].tip = { { left = "Helm" }, { left = "Equip: +40 Attack Power in Cat, Bear, and Dire Bear forms only." },
    { left = "Equip: Increases damage done by Fire spells and effects by up to 20." } }
  local lines = table.concat(H.boot({ client = cl }).ns.CheckLines(), "\n")
  check("check: unread Equip effects counted", lines:find("2 Equip: effect(s) aren't plain stats and weren't counted", 1, true), lines)
end

-- 8. The copy box tells Mac players their shortcut
do
  local h = H.boot(); h.ns.Export()
  check("chat line mentions Cmd+C", table.concat(h.c.printed, "|"):find("Cmd+C", 1, true))
end

H.finish("SimBench audit 6")
