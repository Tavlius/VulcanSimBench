-- Regression tests for audit round 2: mutation-test gaps and the fixes they led to.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end
local function setPieces(cl, setID, slots, tip)
  for _, slot in ipairs(slots) do
    cl.items[slot] = { link = "|Hitem:" .. (20000 + slot) .. ":0|h[P]|h", setID = setID, stats = {}, tip = tip }
  end
end

-- 1. Only "Equip:" lines feed `ie`: an enchant or stat line the game left out is not added
do
  local cl = H.defaultClient()
  cl.items[1].tip = { { left = "Helm" }, { left = "+15 Agility" }, { left = "Enchanted: +8 Stamina" } }
  local F = export({ client = cl })
  check("non-Equip lines never added", F.ie == nil and H.kv(F["is"]).AGI == "31" and H.kv(F["is"]).STA == "15", F["is"])
end

-- 2. Two "Equip:" lines for one stat on one item are summed; aliases within an item never double
do
  local cl = H.defaultClient()
  cl.items[2] = { link = "|Hitem:9:0|h[Neck]|h", stats = { ITEM_MOD_AGILITY_SHORT = 5 },
    tip = { { left = "Neck" }, { left = "Equip: +10 Attack Power." }, { left = "Equip: +12 Attack Power." } } }
  cl.items[11] = { link = "|Hitem:10:0|h[Ring]|h",
    stats = { ITEM_MOD_HIT_RATING_SHORT = 1, ITEM_MOD_HIT_MELEE_RATING_SHORT = 1, ITEM_MOD_CRIT_RATING_SHORT = 2, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 1 } }
  local F = export({ client = cl })
  check("two Equip AP lines summed", H.kv(F.ie).AP == "22", F.ie)
  check("hit alias pair counted once", H.kv(F["is"]).HIT == "1", F["is"])
  check("crit alias pair keeps the larger", H.kv(F["is"]).CRIT == "3", F["is"])   -- ring 2 + bow 1
end

-- 3. Items with stat names the addon doesn't know: no Equip fill (could be the same stat)
do
  local cl = H.defaultClient()
  cl.items[2] = { link = "|Hitem:9:0|h[Neck]|h", stats = { ITEM_MOD_HIT_CHANCE_SHORT = 1 },
    tip = { { left = "Neck" }, { left = "Equip: Improves your chance to hit by 1%." } } }
  local F = export({ client = cl })
  check("unknown stat exported shortened", H.kv(F["is"]).HITCHANCE == "1", F["is"])
  check("unknown stat item: no Equip fill", F.ie == nil, F.ie)
end

-- 4. Set lines read but not recognised vs not readable
do
  local cl = H.defaultClient()
  setPieces(cl, 700, { 1, 5 }, { { left = "Piece" }, { left = "Soulbound" }, { left = "Ensemble: Wildwuchs" } })
  local F, h = export({ client = cl })
  check("unrecognised set lines -> setparse", (F.miss or ""):find("setparse", 1, true)
    and not (F.miss or ""):find("setbonus", 1, true), F.miss)
  check("setparse warning points to debug", notes(h):find("Type /simx debug", 1, true), notes(h))
  local cl2 = H.defaultClient()
  setPieces(cl2, 700, { 1, 5 }, nil)
  local F2 = export({ client = cl2 })
  check("no tooltip -> setbonus", (F2.miss or ""):find("setbonus", 1, true) and not (F2.miss or ""):find("setparse", 1, true), F2.miss)
end

-- 5. No piece's set ID loaded: bonuses kept, flagged so the player re-exports
do
  local cl = H.defaultClient()
  setPieces(cl, nil, { 1, 5 }, { { left = "P" }, { left = "Mystery Set (2/5)" }, { left = "Set: Reduces the cooldown of X." } })
  local F, h = export({ client = cl })
  check("set ID unknown: sbx 0", F.sbx == "0:1", F.sbx)
  check("set ID unknown: flagged", (F.miss or ""):find("setid", 1, true), F.miss)
  check("set ID unknown: warned", notes(h):find("Couldn't tell which set", 1, true), notes(h))
end

-- 6. Set ID 0 from the client means "no set"
do
  local cl = H.defaultClient(); cl.items[1].setID = 0; cl.items[16].setID = 0
  local F = export({ client = cl })
  check("setID 0 is not a set", F.set == nil and not (F.miss or ""):find("set", 1, true), tostring(F.set) .. " " .. tostring(F.miss))
end

-- 7. All resistances (enUS wording and client template), decimals
do
  local ns = H.boot().ns
  local r = ns.ParseSetStat("+8 to All Resistances.")
  check("all resistances via client template", r and r.FIRE == 8 and r.NATURE == 8 and r.FROST == 8 and r.SHADOW == 8 and r.ARCANE == 8)
  _G.ITEM_RESIST_ALL = nil
  r = ns.ParseSetStat("+8 to All Resistances.")
  check("all resistances via English fallback", r and r.FIRE == 8 and r.ARCANE == 8)
  r = ns.ParseSetStat("+8 All Resistances")
  check("all resistances short form", r and r.SHADOW == 8)
  r = ns.ParseSetStat("Improves your chance to get a critical strike by 1.5%.")
  check("decimal bonus", r and r.CRIT == 1.5, r and r.CRIT)
  local cl = H.defaultClient()
  setPieces(cl, 5, { 1, 5 }, { { left = "P" }, { left = "S (2/3)" }, { left = "Set: Improves your chance to get a critical strike by 1.5%." } })
  cl.items[2] = { link = "|Hitem:9:0|h[N]|h", stats = {}, tip = { { left = "N" }, { left = "Equip: Restores 2.5 mana per 5 sec." } } }
  local F = export({ client = cl })
  check("decimal set bonus kept", F.sb == "CRIT:1.5", F.sb)
  check("decimal equip stat kept", H.kv(F.ie).MP5 == "2.5", F.ie)
  check("one-piece 'set' rejected", ns.ParseSetTooltip({ { left = "x" }, { left = "Y (1/1)" } }) == nil)
end

-- 8. Talents: a talent with no position, ranks above the tree total, zero trees, API silent
do
  local cl = H.defaultClient(); table.insert(cl.talents[2].list, { nil, nil, 0 })
  local F = export({ client = cl })
  check("talent without tier/column flagged", (F.miss or ""):find("talents", 1, true), F.miss)
  local cl2 = H.defaultClient(); cl2.talents[1].spentOverride = 9
  local F2 = export({ client = cl2 })
  check("ranks above tree total flagged", (F2.miss or ""):find("talents", 1, true), F2.miss)
  local cl3 = H.defaultClient(); cl3.talents = {}
  local F3 = export({ client = cl3 })
  check("zero talent trees flagged", (F3.miss or ""):find("talents", 1, true), F3.miss)
  local h4 = H.boot()
  _G.C_SpecializationInfo.GetTalentInfo = function() return nil end
  local F4 = h4.ns.Decode(h4.ns.Export())
  check("per-talent call silent -> tree totals only", (F4.miss or ""):find("talentranks", 1, true) and F4.tal == "10-8-0"
    and F4.tr == nil, tostring(F4.miss) .. " " .. tostring(F4.tal))
  check("per-talent call silent -> plain note", notes(h4):find("only reports points per talent tree", 1, true), notes(h4))
  local h5 = H.boot()
  _G.C_SpecializationInfo.GetTalentInfo = function() return nil end
  local origSpec = _G.C_SpecializationInfo.GetSpecializationInfo
  _G.C_SpecializationInfo.GetSpecializationInfo = function(t) local r = { origSpec(t) }; r[7] = nil; return unpack(r, 1, 10) end
  local F5 = h5.ns.Decode(h5.ns.Export())
  check("no talents and no points -> talentapi, no fake 0-0-0", (F5.miss or ""):find("talentapi", 1, true) and F5.tal == nil, F5.miss)
  check("talentapi -> plain warning", notes(h5):find("talent functions didn't answer", 1, true), notes(h5))
end

-- 9. Quiver in the last bag, and the old container API
do
  local cl = H.defaultClient()
  cl.bags = { [4] = { id = 18714, classID = 11, tip = { { left = "Q" }, { left = "Increases ranged attack speed by 15%." } } } }
  local F = export({ client = cl })
  check("quiver in bag 4", F.qv == "15", F.qv)
  local h = H.boot({ client = H.defaultClient() })
  _G.C_Container = nil
  _G.ContainerIDToInventoryID = function(bag) return 19 + bag end
  local F2 = h.ns.Decode(h.ns.Export())
  check("old container API", F2.qv == "15", F2.qv)
  local h3 = H.boot()
  _G.C_Container, _G.ContainerIDToInventoryID = nil, nil
  local F3 = h3.ns.Decode(h3.ns.Export())
  check("no container API: bag slots 20-23 assumed", F3.qv == "15", F3.qv)
end

-- 10. Off-hand slot items with unknown type aren't "unreadable weapons"
do
  local cl = H.defaultClient()
  cl.items[17] = { link = "|Hitem:12602:0|h[Shield]|h", stats = { RESISTANCE0_NAME = 2000 }, tip = { { left = "Shield" }, { left = "2000 Armor" } } }
  local h = H.boot({ client = cl })
  local orig = h.c.instant
  h.c.instant = function(id) if id == 12602 then return id end return orig(id) end
  local F = h.ns.Decode(h.ns.Export())
  check("unknown-type slot 17 without damage: not missing", not (F.miss or ""):find("weapon17", 1, true), F.miss)
  check("unknown-type slot 17: no loc", F.g:find("17:12602:0,", 1, true) or F.g:find("17:12602:0$"), F.g)
end

-- 11. One readable item is not "no item stats"; whole-gear miss has no partial note
do
  local cl = H.defaultClient()
  cl.items[16].stats, cl.items[16].uncached = nil, true
  cl.items[18].stats, cl.items[18].uncached = nil, true
  local F = export({ client = cl })
  check("one readable item: partial, not total", (F.miss or ""):find("itemstats16", 1, true) and not (F.miss or ""):find("itemstats,", 1, true)
    and not (F.miss or ""):match("itemstats$"), F.miss)
  local _, h = export({ noItemStats = true })
  check("no item stats: no 'hadn't loaded' note", not notes(h):find("hadn't loaded", 1, true), notes(h))
end

-- 12. Decimals survive formatting; zero stats dropped; empty fields not written
do
  local cl = H.defaultClient()
  cl.items[1].stats = { ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_SPIRIT_SHORT = 0, ITEM_MOD_POWER_REGEN0_SHORT = 2.5 }
  cl.ammo.tip = { { left = "Ammo" }, { left = "Adds  damage per second" } }
  local F, _, s = export({ client = cl })
  check("decimal item stat", H.kv(F["is"]).MP5 == "2.5", F["is"])
  check("zero stat dropped", not H.kv(F["is"]).SPI, F["is"])
  check("empty field not written", not s:find("ammo=;", 1, true) and not s:find("=;", 1, true), s)
end

-- 13. Checksums: upper-case hex accepted; a string from another format is skipped for a good one after it
do
  local ns = H.boot().ns
  local s = ns.Export()
  local up = s:sub(1, -9) .. s:sub(-8):upper()
  check("upper-case checksum accepted", ns.Decode(up) ~= nil)
  local other = "FSX2:a=1#" .. ns.Adler32("FSX2:a=1")
  check("newer string then ours: ours read", ns.Decode(other .. " " .. s) ~= nil)
  local _, why = ns.Decode(other)
  check("newer format alone: says update", why and why:find("newer", 1, true) and why:find("update", 1, true), why)
  local older = "FSX0:a=1#" .. ns.Adler32("FSX0:a=1")
  local _, why2 = ns.Decode(older)
  check("older format: says export again", why2 and why2:find("older", 1, true), why2)
  check("bad copy then good copy", ns.Decode(s:sub(1, 200) .. "\n" .. s) ~= nil)
  check("Unicode spaces in a pasted string ignored", ns.Decode(s:sub(1, 50) .. "\194\160\226\128\139" .. s:sub(51)) ~= nil)
end

-- 14. Hostile pastes stay fast
do
  local ns = H.boot().ns
  local t0 = os.clock()
  ns.Decode(("FSX1:#00000000"):rep(4000))
  ns.Decode("FSX1:" .. ("#00000000"):rep(7000))
  check("hostile paste decodes fast", os.clock() - t0 < 2, os.clock() - t0)
  local _, why = ns.Decode(("x"):rep(200000))
  check("huge paste refused", why and why:find("too long", 1, true), why)
end

-- 15. StripCodes and TemplatePattern details
do
  local ns = H.boot().ns
  check("StripCodes: |n becomes a space", ns.StripCodes("a|nb") == "a b", ns.StripCodes("a|nb"))
  check("StripCodes: atlas removed", ns.StripCodes("|A:coin:0:0|a5 gold") == "5 gold", ns.StripCodes("|A:coin:0:0|a5 gold"))
  check("TemplatePattern: surrounding spaces allowed", ("  10 Armor "):match(ns.TemplatePattern("%s Armor")) == "10")
  check("TemplatePattern: %.1f", ("Adds 13.5 damage per second"):match(ns.TemplatePattern("Adds %.1f damage per second")) == "13.5")
  check("clean: HTML characters removed", ns.clean('<b>"Tom"&Co</b>') == "bTomCo/b", ns.clean('<b>"Tom"&Co</b>'))
end

-- 16. Errors during export: a plain message, kept for /simx debug
do
  local h = H.boot()
  _G.GetNumTalentTabs = function() error("kaboom") end   -- ns.try swallows this one
  check("API error inside ns.try: export still works", h.ns.Export() ~= nil)
  local orig = h.ns.CollectAll
  h.ns.CollectAll = function() error("unexpected") end
  h.c.printed = {}
  local ok = pcall(h.ns.Export)
  check("internal error: no Lua error escapes", ok)
  check("internal error: plain message", table.concat(h.c.printed, "|"):find("Export failed", 1, true), table.concat(h.c.printed, "|"))
  check("internal error: cache cleared", h.ns.tipCache == nil)
  h.ns.CollectAll = orig
  H.slash("debug")
  check("internal error shown in debug", h.ns.CopyFrame().text:find("Last export error", 1, true))
end

-- 17. /simx check output details
do
  local cl = H.defaultClient(); cl.bags = {}
  local h = H.boot({ client = cl })
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("check: no missing -> nothing", lines:find("Missing: nothing", 1, true), lines)
  local cl2 = H.defaultClient(); cl2.bags[1].tip = { { left = "Q" } }
  local lines2 = table.concat(H.boot({ client = cl2 }).ns.CheckLines(), "\n")
  check("check: one missing entry shown", lines2:find("Missing: quiver", 1, true), lines2)
  local lines3 = table.concat(H.boot({ noTooltipInfo = true, scanTip = true }).ns.CheckLines(), "\n")
  check("check: hidden tooltip explained", lines3:find("(fine: the hidden tooltip is used)", 1, true), lines3)
end

-- 18. Scanning tooltip: a hidden right-hand line from an earlier item is ignored
do
  local cl = H.defaultClient()
  cl.items[16].tip = { { left = "Axe" }, { left = "153 - 256 Damage" }, { left = "Two-Hand" } }   -- no speed shown
  local h = H.boot({ client = cl, noTooltipInfo = true, scanTip = true })
  -- Leave stale text on a hidden right line, as a reused tooltip can.
  local tipFrame = _G.VulcanSimBenchScanTip
  local origSet = tipFrame.SetInventoryItem
  rawset(tipFrame, "SetInventoryItem", function(self, unit, slot)
    origSet(self, unit, slot)
    local R = _G.VulcanSimBenchScanTipTextRight3
    if slot == 16 and R then R.text = "Speed 9.99"; R.shown = false end
  end)
  local F = h.ns.Decode(h.ns.Export())
  check("stale hidden speed ignored", not (F.w or ""):find("9.99", 1, true), F.w)
end

-- 19. /simx verify cleans pasted text
do
  local ns = H.boot().ns
  local body = "FSX1:cls=|Tx:0|tROGUE;lvl=60"
  local msg = ns.VerifyText(body .. "#" .. ns.Adler32(body))
  check("verify: codes stripped from pasted fields", not msg:find("|T", 1, true) and msg:find("ROGUE", 1, true), msg)
end

H.finish("SimBench audit 2")
