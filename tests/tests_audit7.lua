-- Regression tests for audit round 7: sets with no readable bonus lines,
-- zeroed talent answers, GetNumTalents returning 0, crit/ranged-crit twins,
-- main hand without damage, /simx button with no Character panel, line breaks.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end

-- 1. Set name read, bonus lines in an unknown shape: flagged, not silently zero
do
  local cl = H.defaultClient()
  local tip = { { left = "x" }, { left = "Giantstalker Armor (2/8)" }, { left = "Set (2): +40 Attack Power." } }
  for _, slot in ipairs({ 1, 5 }) do cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = {}, tip = tip } end
  local F, h = export({ client = cl })
  check("no readable bonus lines: setparse", (F.miss or ""):find("setparse", 1, true), F.miss)
  check("no readable bonus lines: warned", notes(h):find("didn't show their set the way SimBench expects", 1, true), notes(h))
end

-- 2. Zeroed talent answers past the end don't shift ranks
do
  local h = H.boot({ forever = true })
  local orig = _G.C_SpecializationInfo.GetTalentInfo
  _G.C_SpecializationInfo.GetTalentInfo = function(q)
    return orig(q) or { name = "", tier = 0, column = 0, rank = 0 }
  end
  local F = h.ns.Decode(h.ns.Export())
  check("zeroed answers: ranks unchanged", F.tr == "5032-53-0" and F.miss == nil, tostring(F.tr) .. " " .. tostring(F.miss))
end

-- 3. GetNumTalents returning 0: count by asking
do
  local h = H.boot()
  _G.GetNumTalents = function() return 0 end
  local F = h.ns.Decode(h.ns.Export())
  check("GetNumTalents 0: ranks still read", F.tr == "5032-53-0" and F.miss == nil, tostring(F.tr) .. " " .. tostring(F.miss))
end

-- 4. Ranged crit in Equip text when the item already reports crit: not doubled
do
  local cl = H.defaultClient()
  cl.items[2] = { link = "|Hitem:9:0|h[Neck]|h", stats = { ITEM_MOD_CRIT_RATING_SHORT = 1 },
    tip = { { left = "Neck" }, { left = "Equip: Improves your chance to get a critical strike with missile weapons by 1%." } } }
  local F = export({ client = cl })
  check("crit twin: no RCRIT added", F.ie == nil and not H.kv(F["is"]).RCRIT, tostring(F.ie) .. " " .. F["is"])
end

-- 4b. Both twins in one item's Equip text: both counted (only the item's own stats block a twin)
do
  local cl = H.defaultClient()
  cl.items[2] = { link = "|Hitem:9:0|h[Neck]|h", stats = { ITEM_MOD_AGILITY_SHORT = 3 },
    tip = { { left = "Neck" }, { left = "Equip: Improves your chance to hit by 1%." },
      { left = "Equip: Improves your chance to hit with missile weapons by 1%." } } }
  local F = export({ client = cl })
  check("both twins from Equip text kept", H.kv(F.ie).HIT == "1" and H.kv(F.ie).RHIT == "1", F.ie)
end

-- 4c. 0-based talent answers: answered (not "points per tree only"), and flagged
do
  local h = H.boot({ forever = true })
  local orig = _G.C_SpecializationInfo.GetTalentInfo
  _G.C_SpecializationInfo.GetTalentInfo = function(q)
    local t = orig(q); if t then t.tier, t.column = t.tier - 1, t.column - 1 end; return t
  end
  local F = h.ns.Decode(h.ns.Export())
  check("0-based talents: not reported as points-only", not (F.miss or ""):find("talentranks", 1, true), F.miss)
end

-- 5. A main-hand item with unknown type and no damage line is reported
do
  local cl = H.defaultClient(); cl.items[16].tip = { { left = "Axe" }, { left = "Two-Hand" } }
  local h = H.boot({ client = cl })
  local orig = h.c.instant
  h.c.instant = function(id) if id == 12784 then return id end return orig(id) end
  local F = h.ns.Decode(h.ns.Export())
  check("main hand unknown type, no damage: weapon16 missing", (F.miss or ""):find("weapon16", 1, true), F.miss)
end

-- 6. /simx button without a Character panel says so
do
  local h = H.boot({ noPaperDoll = true, saved = { hideButton = true } })
  H.slash("button")
  local h0 = H.boot({ noPaperDoll = true }); h0.c.printed = {}
  H.slash("button")
  check("button off without a panel: no 'hidden' claim", table.concat(h0.c.printed, "|"):find("turned off", 1, true), table.concat(h0.c.printed, "|"))
  check("button: no panel explained", table.concat(h.c.printed, "|"):find("no Character panel", 1, true), table.concat(h.c.printed, "|"))
end

-- 7. Line breaks in a tree name become spaces
do
  local ns = H.boot().ns
  check("clean: newline is a space", ns.clean("Beast\nMastery") == "Beast+Mastery", ns.clean("Beast\nMastery"))
  check("clean: tab is a space", ns.clean("Beast\tMastery") == "Beast+Mastery")
end

H.finish("SimBench audit 7")
