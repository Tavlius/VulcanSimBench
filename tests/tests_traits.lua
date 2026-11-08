-- Forever's trait talents (Collect.lua: ns.CollectTraitTalents; seen 7 Nov 2026 on client
-- 1.60.1.70862): the active trait config's nodes, exported as ts (ranked talents by spell
-- ID) and tsn (talent nodes read), ahead of the classic per-tree calls.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

-- A Hunter's one trait tree: Deadly Aspects 5/5, Improved Tracking 1/5, Hawk Eye 0/3, and a node with no talent.
local function forever(extra)
  local t = { config = 419637, trees = { [1091] = {
    { 104996, 24293, 1, 5 }, { 104001, 19552, 5, 5 }, { 104002, 19498, 0, 3 }, { 104003, nil, 0, 1 } } } }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local function export(opts) local h = H.boot(opts) return h.ns.Decode(h.ns.Export()), h end

do
  local F, h = export({ traits = forever() })
  check("traits: ranked talents by spell ID", F.ts == "19552:5,24293:1", F.ts)
  check("traits: talent nodes counted (not the node with no spell)", F.tsn == "3", F.tsn)
  check("traits: no classic talent fields beside them", F.tal == nil and F.tr == nil and F.tn == nil, tostring(F.tal) .. " " .. tostring(F.tr))
  check("traits: nothing missing", F.miss == nil, F.miss)
  check("traits: /simx check names the API", h.ns.TalentAPIAvailable() == "C_Traits", h.ns.TalentAPIAvailable())
end
do
  local t = forever(); for _, n in ipairs(t.trees[1091]) do n[3] = 0 end
  local F = export({ traits = t })
  check("traits: none spent: no ts, tsn still says they were read", F.ts == nil and F.tsn == "3" and F.miss == nil, tostring(F.ts) .. " " .. tostring(F.tsn))
end
do
  local t = forever(); t.trees[1091][1][3] = nil
  local F = export({ traits = t })
  check("traits: an unreadable rank is reported, the rest exported", F.miss and F.miss:find("talents", 1, true) and F.ts == "19552:5", tostring(F.miss) .. " " .. tostring(F.ts))
end
do
  local t = forever(); t.trees[1091][4][3] = 1
  local F = export({ traits = t })
  check("traits: a ranked node with no spell is reported", F.miss and F.miss:find("talents", 1, true), F.miss)
end
do   -- one spell on two nodes (Forever's Hunter tree, 7 Nov 2026: Lightning Reflexes twice, one node unranked)
  local t = forever(); t.trees[1091][3][2] = 24293
  local F = export({ traits = t })
  check("traits: one spell on two nodes, one unranked: exported once, nothing missing", F.ts == "19552:5,24293:1" and F.miss == nil and F.tsn == "3", tostring(F.ts) .. " " .. tostring(F.miss))
  t = forever(); t.trees[1091][3][2] = 24293; t.trees[1091][3][3] = 1
  F = export({ traits = t })
  check("traits: ... both at the same rank: exported once", F.ts == "19552:5,24293:1" and F.miss == nil, tostring(F.ts) .. " " .. tostring(F.miss))
  t = forever(); t.trees[1091][3][2] = 24293; t.trees[1091][3][3] = 2
  F = export({ traits = t })
  check("traits: ... at different ranks: reported", F.miss and F.miss:find("talents", 1, true), F.miss)
  t = forever(); t.trees[1091][3][2] = 24293; t.trees[1091][1][3] = 0
  F = export({ traits = t })
  check("traits: ... both unranked: nothing exported for it, nothing missing", F.ts == "19552:5" and F.miss == nil, tostring(F.ts) .. " " .. tostring(F.miss))
end
do
  local F = export({ traits = forever({ secretNode = 104001 }) })
  check("traits: a node the game won't describe is reported", F.miss and F.miss:find("talents", 1, true) and F.ts == "24293:1", tostring(F.miss) .. " " .. tostring(F.ts))
end
do
  local F = export({ traits = forever({ activeEntry = true }) })
  check("traits: read through the active entry too", F.ts == "19552:5,24293:1", F.ts)
end
do
  local F = export({ traits = forever({ config = false }) })
  check("traits: no active config: the classic calls are used", F.ts == nil and F.tsn == nil and F.tal == "10-8-0", tostring(F.tal))
  F = export({ traits = forever({ noDefinition = true }) })
  check("traits: an incomplete trait API: the classic calls are used", F.ts == nil and F.tal == "10-8-0", tostring(F.tal))
  F = export({ traits = forever({ trees = {} }) })
  check("traits: a config with no talent nodes: the classic calls are used", F.tsn == nil and F.tal == "10-8-0", tostring(F.tal))
end
do   -- the Forever client as seen: the trait config, and a C_SpecializationInfo with one spec and no talents
  local c = H.defaultClient()
  c.talents = { { name = "Hunter", list = {} } }
  local F = export({ traits = forever(), client = c, forever = true })
  check("traits: Forever's client: ts and tsn, not the empty classic tree", F.ts == "19552:5,24293:1" and F.tal == nil and F.miss == nil, tostring(F.tal) .. " " .. tostring(F.miss))
end
do   -- /simx check and /simx debug show the trait talents
  local h = H.boot({ traits = forever() })
  local check_ = table.concat(h.ns.CheckLines(), "\n")
  check("traits: /simx check counts points and talents", check_:find("Talents: 6 points in 2 talents (3 read)", 1, true), check_)
  local dbg = table.concat(h.ns.DebugLines(), "\n")
  check("traits: /simx debug shows the config and tree", dbg:find("GetActiveConfigID: 419637", 1, true) and dbg:find("trait tree 1091: 4 nodes", 1, true), dbg)
  check("traits: /simx debug lists each ranked node with its spell", dbg:find("node 104996: spell 24293, rank 1/5", 1, true) and dbg:find("node 104001: spell 19552, rank 5/5", 1, true) and not dbg:find("node 104002", 1, true), dbg)
  local none = table.concat(H.boot().ns.DebugLines(), "\n")
  check("traits: /simx debug without the trait API says so", none:find("C_Traits: absent", 1, true), none)
end
do   -- the Character-panel button: beside Forever's sidebar tabs (they covered it at the panel's top right, 7 Nov 2026)
  local h = H.boot({ sidebarTabs = true })
  local p = h.ns.charButton and h.ns.charButton.points[1]
  check("button: left of the sidebar tabs when they exist", p and p[1] == "RIGHT" and p[2] == _G.PaperDollSidebarTabs and p[3] == "LEFT", p and tostring(p[1]))
  h = H.boot()
  p = h.ns.charButton and h.ns.charButton.points[1]
  check("button: the panel's top right without them", p and p[1] == "TOPRIGHT" and p[2] == _G.PaperDollFrame and p[4] == -40, p and tostring(p[1]))
end
H.finish("SimBench traits")
