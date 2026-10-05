package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

-- 1. Happy path: a full Hunter export
do
  local h = H.boot()
  local ns = h.ns
  local s = ns.Export()
  check("export returns a string", type(s) == "string", s)
  check("starts with format tag", s:match("^FSX1:"), s)
  check("ends with 8-hex checksum", s:match("#%x%x%x%x%x%x%x%x$"), s)
  check("no whitespace in string", not s:find("%s"), s)
  local F, why = ns.Decode(s)
  check("decodes", F ~= nil, why)
  check("class", F.cls == "HUNTER", F.cls)
  check("race", F.race == "Human", F.race)
  check("level", F.lvl == "60", F.lvl)
  check("build", F.b == "1.60.1.70009", F.b)
  check("talent points by tree", F.tal == "10-8-0", F.tal)
  -- BM list order in mock: (1,2,5) (1,3,0) (2,1,3) (2,2,2) -> sorted by tier,col: 5 0 3 2
  check("talent ranks sorted tier/column", F.tr == "5032-53-0", F.tr)
  check("talent tree names, spaces as +", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
  check("no Discord-formatting characters", not s:find("[_%*~`]"), s)
  check("gear list has helm with id", F.g:find("1:16846:0", 1, true), F.g)
  check("gear list has enchant + loc on weapon", F.g:find("16:12784:1900:2H", 1, true), F.g)
  check("ammo in gear as slot 0", F.g:find("0:11630:0", 1, true), F.g)
  check("melee weapon damage + loc", F.w:find("16:153:256:3.8:2H", 1, true), F.w)
  check("ranged ignores +fire line", F.w:find("18:82:124:3.3:RG", 1, true), F.w)
  check("ammo dps", F.ammo == "17.5", F.ammo)
  check("quiver haste", F.qv == "15", F.qv)
  check("item stats summed", F["is"]:find("AGI:31", 1, true), F["is"])
  check("weapon DPS not counted as a stat", not F["is"]:find("DAMAGE", 1, true), F["is"])
  check("armor stat name", F["is"]:find("ARMOR:300", 1, true), F["is"])
  check("crit item stat", F["is"]:find("CRIT:1", 1, true), F["is"])
  check("sheet ap total includes buffs", F.sh:find("ap:700", 1, true), F.sh)
  check("unbuffed agi = effective - buffs", F.bs:find("agi:240", 1, true), F.bs)
  check("unbuffed ap = base", F.bs:find("ap:600", 1, true), F.bs)
  check("auras", F.au == "1126,27681", F.au)
  check("nothing missing", F.miss == nil, F.miss)
  check("saved per character", VulcanSimBenchCharDB and VulcanSimBenchCharDB.last == s)
  local cf = ns.CopyFrame()
  check("copy box shown with the string", cf and cf.shown and cf.text == s)
  check("character button made", ns.charButton ~= nil)
end

-- 2. Combat: refuses, prints why, never touches stats
do
  local cl = H.defaultClient(); cl.lockdown = true
  local h = H.boot({ client = cl })
  local s = h.ns.Export()
  check("combat: no export", s == nil)
  local said = table.concat(h.c.printed, "\n")
  check("combat: explains", said:find("combat", 1, true), said)
  check("combat: no copy box", h.ns.CopyFrame() == nil)
end
do  -- UnitAffectingCombat secret counts as in combat
  local cl = H.defaultClient(); cl.secret = { combat = true }
  local h = H.boot({ client = cl })
  check("secret combat flag treated as combat", h.ns.Export() == nil)
end

-- 3. Secret values out of combat: fields are dropped, nothing throws
do
  local cl = H.defaultClient(); cl.secret = { crit = true, ap = true, rank = true, aura = true, stat = true, link = true, tip = true }
  local ok, s = pcall(function() return H.boot({ client = cl }).ns.Export() end)
  check("secrets don't throw", ok, s)
  if ok then
    local F = H.boot().ns.Decode(s)
    check("secret crit dropped", F and not (F.sh or ""):find("crit:12", 1, true), F and F.sh)
    check("missing lists sheet fields", F and (F.miss or ""):find("sheet.crit", 1, true), F and F.miss)
  end
end

-- 4. Checksum and decode errors
do
  local ns = H.boot().ns
  local s = ns.Export()
  check("cut-off string rejected", ns.Decode(s:sub(1, -5)) == nil)
  local tampered = s:gsub("lvl=60", "lvl=61")
  check("edited string rejected", ns.Decode(tampered) == nil)
  local wrapped = s:sub(1, 40) .. "\n  " .. s:sub(41)
  check("line-wrapped string still decodes", ns.Decode(wrapped) ~= nil)
  local _, why = ns.Decode("FSX9:a=1#" .. ns.Adler32("FSX9:a=1"))
  check("newer format explained", why and why:find("newer"), why)
  check("garbage rejected", ns.Decode("hello") == nil)
  check("adler32 known value", ns.Adler32("Wikipedia") == "11e60398", ns.Adler32("Wikipedia"))
end

-- 5. Parsers
do
  local ns = H.boot().ns
  local w = ns.ParseWeapon({ { left = "Bow" }, { left = "82 - 124 Damage", right = "Speed 3.30" } })
  check("weapon parse", w and w.min == 82 and w.max == 124 and w.speed == 3.3)
  w = ns.ParseWeapon({ { left = "X" }, { left = "82 - 124 Damage" }, { left = "y", right = "Speed 3.30" } })
  check("speed on its own line", w and w.speed == 3.3)
  check("no damage line -> nil", ns.ParseWeapon({ { left = "Ring" } }) == nil)
  check("nil lines -> nil", ns.ParseWeapon(nil) == nil)
  check("ammo parse", ns.ParseAmmo({ { left = "Pellets" }, { left = "Adds 17.5 damage per second" } }) == 17.5)
  check("quiver parse", ns.ParseQuiver({ { left = "Quiver 15%" }, { left = "Increases ranged attack speed by 13%." } }) == 13)
  check("decimal comma", ns.ToNumber("2,60") == 2.6)
  check("thousands comma", ns.ToNumber("1,234") == 1234)
  check("fmt trims zeros", ns.fmt(2.60) == "2.6" and ns.fmt(13) == "13" and ns.fmt(-0.001) == "0")
  check("fmt rejects NaN", ns.fmt(0/0) == nil)
  check("clean strips separators", ns.clean("a;b=c,d:e#f|g h") == "abcdefg+h", ns.clean("a;b=c,d:e#f|g h"))
  check("clean strips markdown", ns.clean("a_b*c~d`e+f") == "abcdef", ns.clean("a_b*c~d`e+f"))
end

-- 6. German client: localized templates and decimal commas
do
  local cl = H.defaultClient()
  cl.items[16].tip = { { left = "Arkanitschnitter" }, { left = "153 - 256 Schaden", right = "Tempo 3,80" } }
  cl.ammo.tip = { { left = "Kugeln" }, { left = "Verursacht 17,5 Schaden pro Sekunde" } }
  local h = H.boot({ client = cl, damageTemplate = "%s - %s Schaden", ammoTemplate = "Verursacht %s Schaden pro Sekunde" })
  local F = h.ns.Decode(h.ns.Export())
  check("de: weapon", F.w:find("16:153:256:3.8", 1, true), F.w)
  check("de: ammo", F.ammo == "17.5", F.ammo)
end

-- 7. Old/odd clients
do  -- no tooltip text at all (neither API nor the hidden tooltip): weapons reported missing
  local h = H.boot({ noTooltipInfo = true, noScanTip = true })
  local F = h.ns.Decode(h.ns.Export())
  check("no tooltip text: still exports", F ~= nil)
  check("no tooltip text: weapons reported missing", F.miss and F.miss:find("weapon16", 1, true), F.miss)
end
do
  local h = H.boot({ noTalents = true })
  local F = h.ns.Decode(h.ns.Export())
  check("no talent API: missing talents", F.miss and F.miss:find("talents", 1, true) and not F.tal, F.miss)
  local said = table.concat(h.ns.lastNotes, "\n")
  check("no talent API: tells the player", said:find("talents", 1, true), said)
end
do
  local h = H.boot({ wrathTabInfo = true, legacyTalents = true })
  local F = h.ns.Decode(h.ns.Export())
  check("tab info with numeric id first", F.tn == "Beast+Mastery,Marksmanship,Survival", F.tn)
end
do
  local h = H.boot({ noItemStats = true })
  local F = h.ns.Decode(h.ns.Export())
  check("no item stats: flagged", F.miss and F.miss:find("itemstats", 1, true), F.miss)
end
do
  local cl = H.defaultClient(); cl.bags = {}; cl.ammo = nil
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("no quiver: field absent", F.qv == nil)
  local said = table.concat(h.ns.lastNotes, "\n")
  check("no quiver: hunter warned", said:find("quiver", 1, true), said)
end
do
  local cl = H.defaultClient(); cl.level = 42
  local h = H.boot({ client = cl })
  h.ns.Export()
  check("low level warned", table.concat(h.ns.lastNotes, "\n"):find("level 42", 1, true))
end
do
  local h = H.boot({ noPaperDoll = true })
  check("no character panel: no button, no error", h.ns.charButton == nil)
end

-- 8. Slash commands
do
  local h = H.boot()
  H.slash("check")
  local said = table.concat(h.c.printed, "\n")
  check("/simx check prints talents", said:find("Beast Mastery 10", 1, true), said)
  check("/simx check prints weapon", said:find("Weapon slot 18: 82 - 124, speed 3.3 (RG)", 1, true), said)
  h.c.printed = {}
  H.slash("last")
  check("/simx last with nothing saved", table.concat(h.c.printed):find("No export yet", 1, true))
  local s = h.ns.Export()
  -- verify opens a paste box (chat input is capped at 255 characters).
  H.slash("verify " .. s)
  local cf = h.ns.CopyFrame()
  check("/simx verify opens an empty paste box", cf.shown and cf.onPaste and h.ns.lastNotes[1]:find("Paste", 1, true))
  local box
  for _, fr in ipairs(h.c.frames) do if fr.kind == "EditBox" then box = fr end end
  check("/simx verify box starts empty", box.text == "", box.text)
  box.text = "here you go: " .. s .. " thanks"
  box.scripts.OnTextChanged(box, true)
  check("/simx verify keeps pasted text", box.text:find(s, 1, true))
  check("/simx verify ok, shown under the box", h.ns.lastNotes[1]:find("complete:|r HUNTER level 60", 1, true), h.ns.lastNotes[1])
  box.text = s:sub(1, 300)
  box.scripts.OnTextChanged(box, true)
  check("/simx verify bad", h.ns.lastNotes[1]:find("problem", 1, true), h.ns.lastNotes[1])
  check("verify counts items (not ammo)", h.ns.VerifyText(s):find("3 items", 1, true), h.ns.VerifyText(s))
  -- The copy box goes back to protecting the string afterwards.
  local s2 = h.ns.Export()
  box.text = s2 .. "x"
  box.scripts.OnTextChanged(box, true)
  check("after verify, copy box protects again", box.text == s2)
  H.slash("items")
  check("/simx items shows raw stats", h.ns.CopyFrame().text:find("ITEM_MOD_AGILITY_SHORT=20", 1, true), h.ns.CopyFrame().text)
  h.c.printed = {}
  H.slash("bogus")
  check("unknown command shows help", table.concat(h.c.printed):find("/simx check", 1, true))
  VulcanSimBench_OnAddonCompartmentClick()
  check("compartment click exports", h.ns.CopyFrame().text:match("^FSX1:"))
end

-- 9. Copy box protects the string from edits
do
  local h = H.boot()
  local s = h.ns.Export()

  local box
  for _, fr in ipairs(h.c.frames) do if fr.kind == "EditBox" then box = fr end end
  box.text = s .. "x"
  box.scripts.OnTextChanged(box, true)
  check("typing in the box restores the string", box.text == s)
end

-- 10. Determinism: same character, same string
do
  local a = H.boot().ns.Export()
  local b = H.boot().ns.Export()
  check("deterministic", a == b)
end

-- 11. Loop 1 fixes
do  -- shield in the off-hand: recorded, not a "missing weapon"
  local cl = H.defaultClient()
  cl.items[16] = { link = "|Hitem:810:0|h[Hammer]|h", loc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_STRENGTH_SHORT = 5 },
    tip = { { left = "Hammer" }, { left = "59 - 110 Damage", right = "Speed 2.40" } } }
  cl.items[17] = { link = "|Hitem:12602:0|h[Draconian Deflector]|h", loc = "INVTYPE_SHIELD",
    stats = { RESISTANCE0_NAME = 2500, ITEM_MOD_BLOCK_VALUE_SHORT = 30 }, tip = { { left = "Draconian Deflector" }, { left = "2500 Armor" } } }
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("shield: no missing weapon17", not (F.miss or ""):find("weapon17", 1, true), F.miss)
  check("shield: loc recorded", F.g:find("17:12602:0:SH", 1, true), F.g)
  check("shield: no weapon entry", not F.w:find("17:", 1, true), F.w)
  check("shield: block value", F["is"]:find("BV:30", 1, true), F["is"])
  check("shield: no warning about slot 17", not table.concat(h.ns.lastNotes):find("slot 17", 1, true))
end
do  -- single-damage weapon line
  local ns = H.boot().ns
  local w = ns.ParseWeapon({ { left = "Wand" }, { left = "40 Damage", right = "Speed 1.50" } })
  check("single damage template", w and w.min == 40 and w.max == 40 and w.speed == 1.5)
end
do  -- one item's stats unreadable (its tooltip shows stats): totals flagged as partial
  local cl = H.defaultClient(); cl.items[1].stats = nil; cl.items[1].uncached = true
  cl.items[1].tip = { { left = "Helm" }, { left = "300 Armor" }, { left = "+20 Agility" } }
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("partial stats flagged", (F.miss or ""):find("itemstats1", 1, true), F.miss)
  check("partial stats explained", table.concat(h.ns.lastNotes):find("hadn't loaded yet (Head)", 1, true), table.concat(h.ns.lastNotes))
end
do  -- shirt with no stats is not "partial"
  local cl = H.defaultClient()
  cl.items[4] = { link = "|Hitem:45:0|h[Shirt]|h", stats = nil }
  local F = H.boot({ client = cl }).ns
  local d = F.Decode(F.Export())
  check("shirt ignored for partial check", not (d.miss or ""):find("itemstats4", 1, true), d.miss)
end
do  -- quiver found but unreadable
  local cl = H.defaultClient(); cl.bags[1].tip = { { left = "Quiver" }, { left = "Soulbound" } }
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("quiver unreadable flagged", (F.miss or ""):find("quiver", 1, true), F.miss)
end
do  -- item data not loaded yet (no equip loc): still reads weapon damage
  local cl = H.defaultClient(); cl.items[18].loc = nil
  local orig = cl.instant
  local h = H.boot({ client = cl })
  h.c.instant = function(id) if id == 18713 then return id end return orig(id) end
  local F = h.ns.Decode(h.ns.Export())
  check("unloaded loc: damage still read", F.w and F.w:find("18:82:124:3.3", 1, true), F.w)
end
do  -- button toggle
  local h = H.boot()
  H.slash("button")
  check("button hidden", VulcanSimBenchCharDB.hideButton == true and not h.ns.charButton.shown)
  H.slash("button")
  check("button shown again", VulcanSimBenchCharDB.hideButton == false and h.ns.charButton.shown)
  local h2 = H.boot({ saved = { hideButton = true } })
  check("hidden button stays hidden after reload", h2.ns.charButton == nil)
end
do  -- one chat line per export
  local h = H.boot()
  h.c.printed = {}
  h.ns.Export()
  check("one chat line", #h.c.printed == 1, #h.c.printed)
end

do  -- combat starts between the check's two combat tests
  local h = H.boot()
  local n = 0
  local orig = _G.InCombatLockdown
  _G.InCombatLockdown = function() n = n + 1; return n > 2 end
  local ok, lines = pcall(h.ns.CheckLines)
  _G.InCombatLockdown = orig
  check("check survives combat starting mid-way", ok, lines)
  check("check says combat started", ok and table.concat(lines, "\n"):find("Combat started", 1, true), ok and table.concat(lines, "|"))
end

-- 12. Loop 2: faction, sets, key binding
do
  local F = H.boot().ns
  local d = F.Decode(F.Export())
  check("faction exported", d.fac == "Alliance", d.fac)
  check("no set field without set pieces", d.set == nil, d.set)
end
do
  local cl = H.defaultClient()
  cl.items[1].setID = 515
  cl.items[5] = { link = "|Hitem:16845:0|h[Chest]|h", stats = { ITEM_MOD_AGILITY_SHORT = 10 }, setID = 515 }
  local h = H.boot({ client = cl })
  local d = h.ns.Decode(h.ns.Export())
  check("set pieces counted", d.set == "515:2", d.set)
  -- No tooltips on these mock pieces, so the set bonuses can't be read.
  check("unreadable set bonus flagged", (d.miss or ""):find("setbonus", 1, true), d.miss)
  check("set warning shown", table.concat(h.ns.lastNotes):find("set bonuses", 1, true), table.concat(h.ns.lastNotes))
end
do
  local cl = H.defaultClient(); cl.items[1].setID = 515
  local h = H.boot({ client = cl })
  h.ns.Export()
  check("one set piece: no warning", not table.concat(h.ns.lastNotes):find("set bonus", 1, true))
end
do
  local h = H.boot()
  check("binding globals", BINDING_NAME_VULCANSIMBENCH_EXPORT and type(VulcanSimBench_Export) == "function")
  VulcanSimBench_Export()
  check("binding exports", h.ns.CopyFrame() and h.ns.CopyFrame().text:match("^FSX1:"))
  local xml = io.open((os.getenv("SX_DIR") or "../") .. "Bindings.xml"):read("*a")
  check("Bindings.xml calls the global", xml:find("VulcanSimBench_Export()", 1, true) and xml:find('name="VULCANSIMBENCH_EXPORT"', 1, true))
end

do  -- /simx last keeps the notes
  local cl = H.defaultClient(); cl.level = 42
  local h = H.boot({ client = cl })
  h.ns.Export()
  H.slash("last")
  local n = table.concat(h.ns.lastNotes, "|")
  check("/simx last shows saved notes", n:find("last export", 1, true) and n:find("level 42", 1, true), n)
end

do
  local cl = H.defaultClient(); cl.secret = { class = true }
  local h = H.boot({ client = cl })
  h.ns.Export()
  check("class unreadable warned", table.concat(h.ns.lastNotes):find("class", 1, true))
end

-- 13. Loop 3: debug dump and the scanning-tooltip fallback
do
  local cl = H.defaultClient(); cl.secret = { crit = true }
  local h = H.boot({ client = cl })
  H.slash("debug")
  local text = h.ns.CopyFrame().text
  check("debug dump opens", text:find("debug dump", 1, true), text)
  check("debug shows talent API returns", text:find('GetSpecializationInfo(1): 101, "Beast Mastery"', 1, true)
    and text:find('GetTalentInfo(1,1): column 2, icon "icon", maxRank 5, name "T1", rank 2, tier 2', 1, true), text)
  check("debug shows tooltip lines", text:find('tip 3: "153 - 256 Damage" | "Speed 3.80"', 1, true), text)
  check("debug shows secrets safely", text:find("GetCritChance: <secret>", 1, true), text)
  check("debug shows equip loc", text:find('"INVTYPE_RANGED"', 1, true), text)
  check("debug shows quiver bag", text:find("Bag 1 (inv 20)", 1, true), text)
  check("debug escapes pipes", not text:find("[^|]|H", 1) , text)
end
do
  local h = H.boot()
  local orig = _G.GetCritChance
  _G.GetCritChance = function() error("boom") end
  local ok, lines = pcall(h.ns.DebugLines)
  _G.GetCritChance = orig
  check("debug survives an erroring API", ok and table.concat(lines, "\n"):find("GetCritChance: (error", 1, true), ok and table.concat(lines, "|"))
end
do  -- no C_TooltipInfo: the hidden GameTooltip is scanned line by line
  local cl = H.defaultClient()
  local h = H.boot({ client = cl, noTooltipInfo = true, scanTip = true })
  local F = h.ns.Decode(h.ns.Export())
  check("scan tooltip: melee weapon read", F.w and F.w:find("16:153:256:3.8", 1, true), F.w)
  check("scan tooltip: ranged weapon read", F.w and F.w:find("18:82:124:3.3", 1, true), F.w)
  check("scan tooltip: ammo read", F.ammo == "17.5", F.ammo)
  check("scan tooltip: quiver read", F.qv == "15", F.qv)
  check("scan tooltip hidden after use", not _G.VulcanSimBenchScanTip.shown)
end

-- write a sample for the JS cross-check
do
  local s = H.boot().ns.Export()
  local fh = io.open("./sample_hunter.txt", "w"); fh:write(s); fh:close()
end

H.finish("SimBench Lua")
