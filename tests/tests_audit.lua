-- Regression tests for the 1.1 audit fixes (talent API, item cache, set IDs,
-- equip text, tooltip codes, decoding pasted text, warnings).
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end

-- 1. Talent APIs: modern, legacy only, both, neither
do
  local F = export()
  check("modern talent API: points", F.tal == "10-8-0", F.tal)
  check("modern talent API: ranks sorted from shuffled order", F.tr == "5032-53-0", F.tr)
  check("modern talent API: names", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
  local L = export({ legacyTalents = true })
  check("legacy-only talent API gives the same", L.tal == F.tal and L.tr == F.tr and L.tn == F.tn, L.tr)
  local B = export({ alsoLegacy = true })
  check("both APIs: same result", B.tr == F.tr)
  local N, h = export({ noTalents = true })
  check("no talent API: missing", (N.miss or ""):find("talents", 1, true) and N.tal == nil, N.miss)
  check("no talent API: warned", notes(h):find("talents", 1, true))
end
do  -- a rank that comes back secret: exported as 0 but flagged, never silent
  local cl = H.defaultClient(); cl.secret = { rank = true }
  local F, h = export({ client = cl })
  check("secret ranks: talents flagged missing", (F.miss or ""):find("talents", 1, true), F.miss)
  check("secret ranks: warned", notes(h):find("Couldn't read all your talents", 1, true), notes(h))
end
do  -- the tree's own points total disagrees with the ranks read
  local cl = H.defaultClient(); cl.talents[1].spentOverride = 11
  local F = export({ client = cl })
  check("points mismatch flagged", (F.miss or ""):find("talents", 1, true), F.miss)
end
do  -- secret tree name: no name, nothing thrown
  local cl = H.defaultClient(); cl.secret = { tabname = true }
  local ok, F = pcall(export, { client = cl })
  check("secret tree name: no error", ok, F)
  check("secret tree name: talents still read", ok and F.tr == "5032-53-0", ok and F.tr)
end
do  -- level 60 with no points spent: a note, not a "missing"
  local cl = H.defaultClient()
  for _, t in ipairs(cl.talents) do for _, x in ipairs(t.list) do x[3] = 0 end end
  local F, h = export({ client = cl })
  check("no points: not missing", not (F.miss or ""):find("talents", 1, true), F.miss)
  check("no points: noted", notes(h):find("No talent points found", 1, true), notes(h))
  cl.level = 8
  local _, h2 = export({ client = cl })
  check("no points under 10: no note", not notes(h2):find("No talent points", 1, true))
end

-- 2. Items the client hasn't loaded yet
do
  local cl = H.defaultClient(); cl.items[1].uncached = true; cl.items[1].stats = {}
  local F, h = export({ client = cl })
  check("uncached item with empty stats: flagged", (F.miss or ""):find("itemstats1", 1, true), F.miss)
  check("uncached item: data requested", h.c.requested and h.c.requested[1] == 16846, h.c.requested and h.c.requested[1])
  check("uncached item: plain warning", notes(h):find("Some items hadn't loaded yet (Head)", 1, true), notes(h))
  local cl2 = H.defaultClient(); cl2.items[1].uncached = true   -- stats still readable: fine
  local F2 = export({ client = cl2 })
  check("uncached item with stats: counted", H.kv(F2["is"]).AGI == "31" and not (F2.miss or ""):find("itemstats1", 1, true), F2["is"])
  local cl3 = H.defaultClient(); cl3.items[2] = { link = "|Hitem:5:0|h[Trinket]|h", stats = {} }   -- cached, truly no stats
  local F3 = export({ client = cl3 })
  check("cached item with no stats: not flagged", not (F3.miss or ""):find("itemstats2", 1, true), F3.miss)
end

-- 3. Set IDs when some pieces aren't cached: the ID is filled in from the others
do
  local cl = H.defaultClient()
  local tip = { { left = "x" }, { left = "Giantstalker Armor (3/8)" }, { left = "" },
    { left = "Set: Improves your chance to hit by 1%." }, { left = "Set: Increases the range of Mend Pet." },
    { left = "(5) Set: +40 Attack Power." } }
  for _, slot in ipairs({ 1, 5, 7 }) do
    cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = { ITEM_MOD_AGILITY_SHORT = 1 }, tip = tip }
  end
  cl.items[1].uncached = true   -- the first piece read has no set ID
  local F, h = export({ client = cl })
  check("backfill: set ID found", F.sbx == "515:2", F.sbx)
  check("backfill: piece count from tooltip", F.set == "515:3", F.set)
  check("backfill: not flagged missing", not (F.miss or ""):find("setbonus", 1, true), F.miss)
  check("backfill: no contradicting notes", not notes(h):find("Couldn't read your set", 1, true), notes(h))
end

-- 4. Localized templates that end in a period (deDE-style)
do
  local cl = H.defaultClient()
  local tip = { { left = "x" }, { left = "Set (2/3)" }, { left = "Satz: Erhöht die Angriffskraft um 40." } }
  cl.items[1].setID, cl.items[1].tip = 9, tip
  cl.items[5] = { link = "|Hitem:7:0|h[y]|h", setID = 9, stats = {}, tip = tip }
  local _, h = export({ client = cl })
  local ns = h.ns
  _G.ITEM_MOD_ATTACK_POWER = "Erhöht die Angriffskraft um %s."
  local st = ns.ParseSetStat("Erhöht die Angriffskraft um 40.")
  check("template with trailing period matches", st and st.AP == 40, st and next(st))
  _G.ITEM_SET_BONUS = "Satz: %s"
  local set = ns.ParseSetTooltip(tip)
  check("localized set bonus prefix", set and set.bonuses[1] and set.bonuses[1].active, set and #set.bonuses)
end

-- 5. "Equip:" stats the game's item stats leave out
do
  local cl = H.defaultClient()
  cl.items[1].tip = { { left = "Helm" }, { left = "+20 Agility" },
    { left = "Equip: Improves your chance to hit by 1%." },
    { left = "Equip: +28 Attack Power when fighting Undead." },
    { left = "Equip: Improves your chance to get a critical strike by 1%." } }
  cl.items[18].tip[#cl.items[18].tip + 1] = { left = "Equip: Improves your chance to get a critical strike by 1%." }
  local F, h = export({ client = cl })
  local is, ie = H.kv(F["is"]), H.kv(F.ie)
  check("equip hit added", is.HIT == "1" and ie.HIT == "1", F["is"] .. " / " .. tostring(F.ie))
  check("equip crit on helm added (helm had none)", ie.CRIT == "1", F.ie)
  check("crit not doubled on the bow (already a stat)", is.CRIT == "2", F["is"])
  check("conditional equip AP not added", is.AP == "62", F["is"])
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("/simx check shows equip text stats", lines:find("read from Equip: text: CRIT 1, HIT 1", 1, true), lines)
  local cl2 = H.defaultClient(); cl2.items[1].stats = nil; cl2.items[1].uncached = true
  cl2.items[1].tip = { { left = "Helm" }, { left = "Equip: Improves your chance to hit by 1%." } }
  local F2 = export({ client = cl2 })
  check("unreadable item: equip text not used", F2.ie == nil and not H.kv(F2["is"]).HIT, F2.ie)
  -- Loaded, no stats from the game, nothing but an Equip line: a statless item whose hit counts.
  local cl3 = H.defaultClient(); cl3.items[2] = { link = "|Hitem:9:0|h[Neck]|h", stats = nil,
    tip = { { left = "Neck" }, { left = "Equip: Improves your chance to hit by 1%." } } }
  local F3 = export({ client = cl3 })
  check("statless loaded item: equip hit counted", F3.ie == "HIT:1" and not (F3.miss or ""):find("itemstats2", 1, true), F3.ie)
  check("no equip text: no ie field", export().ie == nil)
end

-- 6. Colour and texture codes in tooltip text
do
  local cl = H.defaultClient()
  local tip = { { left = "|cffa335eeHelm|r" }, { left = "|cffffd100Giantstalker Armor (3/8)|r" },
    { left = "|cff00ff00Set: Improves your chance to hit by 1%.|r" } }
  for _, slot in ipairs({ 1, 5, 7 }) do
    cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = {}, tip = tip }
  end
  cl.items[16].tip[3] = { left = "|cffffffff153 - 256 Damage|r", right = "|cffffffffSpeed 3.80|r" }
  local F = export({ client = cl })
  check("coloured set lines read", F.sb == "HIT:1", F.sb)
  check("coloured weapon line read", (F.w or ""):find("16:153:256:3.8:2H", 1, true), F.w)
  local ns = H.boot().ns
  check("StripCodes: texture", ns.StripCodes("|TInterface\\Icons\\x:0|tAgility") == "Agility", ns.StripCodes("|TInterface\\Icons\\x:0|tAgility"))
  check("StripCodes: quality colour", ns.StripCodes("|cnIQ4:Epic|r") == "Epic", ns.StripCodes("|cnIQ4:Epic|r"))
  check("StripCodes: link", ns.StripCodes("|Hitem:1|h[X]|h") == "[X]", ns.StripCodes("|Hitem:1|h[X]|h"))
  check("StripCodes: secret", ns.StripCodes(H.SECRET) == nil)
end

-- 7. clean(): Unicode spaces and zero-width characters
do
  local ns = H.boot().ns
  check("clean: NBSP becomes +", ns.clean("Beast\194\160Mastery") == "Beast+Mastery", ns.clean("Beast\194\160Mastery"))
  check("clean: ideographic space", ns.clean("a\227\128\128b") == "a+b")
  check("clean: zero-width removed", ns.clean("a\226\128\139b\239\187\191") == "ab")
  check("clean: texture code removed", ns.clean("|Tx:0|tName") == "Name", ns.clean("|Tx:0|tName"))
  check("clean: accented letters kept", ns.clean("Überleben") == "Überleben")
end

-- 8. Decoding pasted text (the in-game verify box)
do
  local ns = H.boot().ns
  local s = ns.Export()
  check("decode: text before", ns.Decode("my hunter: " .. s) ~= nil)
  check("decode: text after", ns.Decode(s .. " thanks!") ~= nil)
  check("decode: FSX in the text before", ns.Decode("FSX string for my hunter: " .. s) ~= nil)
  check("decode: pasted twice", ns.Decode(s .. "\n" .. s) ~= nil)
  check("decode: #hex after", ns.Decode(s .. " see #deadbeef") ~= nil)
  local _, why = ns.Decode(s:sub(1, -3))
  check("decode: cut off -> no checksum", why and why:find("cut off", 1, true), why)
  local _, why2 = ns.Decode((s:gsub("lvl=60", "lvl=61")))
  check("decode: tampered -> mismatch", why2 and why2:find("mismatch", 1, true), why2)
  local _, why3 = ns.Decode("hello")
  check("decode: not a string", why3 == "not a SimBench string", why3)
  local _, why4 = ns.Decode("FSX9:a=1#" .. ns.Adler32("FSX9:a=1"))
  check("decode: newer format", why4 and why4:find("newer", 1, true), why4)
  local F = ns.Decode("junk " .. s)
  check("decode: fields intact after junk", F and F.cls == "HUNTER" and F.v == ns.VERSION, F and F.v)
end

-- 9. Quiver: the haste line wins over other percentages
do
  local ns = H.boot().ns
  check("quiver: attack speed line preferred", ns.ParseQuiver({ { left = "Quiver" }, { left = "Durability 5%" },
    { left = "Increases ranged attack speed by 14%." } }) == 14)
  check("quiver: fallback first percent", ns.ParseQuiver({ { left = "Köcher" }, { left = "Erhöht Tempo um 13%." } }) == 13)
  local cl = H.defaultClient()
  cl.bags = { [1] = { id = 4500, classID = 1, tip = { { left = "Bag" }, { left = "10% off" } } },
    [2] = { id = 18714, classID = 11, tip = { { left = "Q" }, { left = "Increases ranged attack speed by 15%." } } } }
  local F = export({ client = cl })
  check("quiver found after a normal bag (item class checked)", F.qv == "15", F.qv)
end

-- 10. Warnings fire for the right people
do
  local cl = H.defaultClient(); cl.ammo = nil
  local _, h = export({ client = cl })
  check("hunter without ammo warned", notes(h):find("No ammo found", 1, true), notes(h))
  local w = H.defaultClient(); w.class = "WARRIOR"; w.ammo = nil; w.bags = {}
  local _, hw = export({ client = w })
  check("warrior: no quiver or ammo notes", not notes(hw):find("quiver", 1, true) and not notes(hw):find("ammo", 1, true), notes(hw))
  local q = H.defaultClient(); q.bags[1].tip = { { left = "Quiver" } }
  local _, hq = export({ client = q })
  check("unreadable quiver: one clear note", notes(hq):find("Found your quiver but couldn't read its haste", 1, true)
    and not notes(hq):find("No quiver", 1, true), notes(hq))
  local wcl = H.defaultClient(); wcl.items[16].tip = { { left = "Axe" } }
  local _, hwp = export({ client = wcl })
  check("weapon warning names the slot", notes(hwp):find("Couldn't read weapon damage (Main Hand)", 1, true), notes(hwp))
  local _, hn = export()
  check("default hunter: no notes at all", #hn.ns.lastNotes == 0, notes(hn))
end

-- 11. Combat blocks the diagnostic commands too
do
  local cl = H.defaultClient(); cl.lockdown = true
  local h = H.boot({ client = cl })
  H.slash("items"); H.slash("debug")
  check("items/debug refused in combat", h.ns.CopyFrame() == nil and table.concat(h.c.printed, "|"):find("Leave combat", 1, true))
  H.slash("")
  check("combat message is plain", table.concat(h.c.printed, "|"):find("Can't export during combat", 1, true), table.concat(h.c.printed, "|"))
end

-- 12. Exact values on the default export (no substring look-alikes)
do
  local F = export()
  local is, sh, bs = H.kv(F["is"]), H.kv(F.sh), H.kv(F.bs)
  check("exact: AGI", is.AGI == "31", F["is"])
  check("exact: CRIT (not SCRIT/RCRIT)", is.CRIT == "1" and is.SCRIT == nil and is.RCRIT == nil, F["is"])
  check("exact: STR, AP, ARMOR, STA", is.STR == "13" and is.AP == "62" and is.ARMOR == "300" and is.STA == "15", F["is"])
  check("exact: sheet ap/rap", sh.ap == "700" and sh.rap == "1050", F.sh)
  check("exact: sheet crit/rcrit/hit/armor", sh.crit == "12.3" and sh.rcrit == "14.1" and sh.hit == "3" and sh.armor == "2100", F.sh)
  check("exact: unbuffed", bs.agi == "240" and bs.ap == "600" and bs.rap == "900" and bs.str == "70", F.bs)
  local g = {}
  for part in F.g:gmatch("[^,]+") do g[#g + 1] = part end
  check("exact: gear list", table.concat(g, ",") == "1:16846:0,16:12784:1900:2H,18:18713:0:RG,0:11630:0", F.g)
end

-- 13. Modern item links (empty fields, quality colour)
do
  local cl = H.defaultClient()
  cl.items[1].link = "|cnIQ4:|Hitem:16846::::::::60:::::|h[Giantstalker's Helmet]|h|r"
  cl.items[16].link = "|cnIQ4:|Hitem:12784:1900:::::::60:::::|h[Arcanite Reaper]|h|r"
  local F = export({ client = cl })
  check("modern link: no enchant -> 0", F.g:find("1:16846:0,", 1, true), F.g)
  check("modern link: enchant read", F.g:find("16:12784:1900:2H", 1, true), F.g)
end

-- 14. Sheet details: faction, debuffs, best spell school, hit vs spell hit
do
  local cl = H.defaultClient()
  cl.faction = "Horde"
  cl.stat[2] = { 125, 250, 20, -10 }                 -- agility with a buff and a debuff
  cl.spellCrit = { [2] = 4, [3] = 9.5, [4] = 6, [5] = 1, [6] = 2, [7] = 3 }
  cl.spellDmg = { [2] = 10, [3] = 40, [4] = 25, [5] = 0, [6] = 5, [7] = 7 }
  cl.hit, cl.shit = 2, 5
  local F = export({ client = cl })
  local sh, bs = H.kv(F.sh), H.kv(F.bs)
  check("faction Horde", F.fac == "Horde", F.fac)
  check("debuff removed from unbuffed agility", bs.agi == "240", F.bs)
  check("best school spell crit", sh.scrit == "9.5", F.sh)
  check("best school spell power", sh.sp == "40", F.sh)
  check("hit and spell hit not swapped", sh.hit == "2" and sh.shit == "5", F.sh)
end

-- 15. Talent rank 10+ and bad weapon lines
do
  local cl = H.defaultClient(); cl.talents[3].list = { { 1, 1, 11 } }
  local F = export({ client = cl })
  check("rank 11 encoded as b", F.tr:sub(-1) == "b", F.tr)
  local ns = H.boot().ns
  check("weapon: max below min rejected", ns.ParseWeapon({ { left = "x" }, { left = "90 - 50 Damage", right = "Speed 2.00" } }) == nil)
  check("weapon: zero speed rejected", ns.ParseWeapon({ { left = "x" }, { left = "50 - 90 Damage", right = "Speed 0.00" } }) == nil)
end

H.finish("SimBench audit")
