-- Set bonuses (1.1): tooltip parsing, stat sums, dedupe, fallbacks, safety.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

-- A Classic-style set-piece tooltip. bonuses = { { n, text }, ... }; a bonus is
-- active (shown as "Set: ...") when have >= n.
local function setTip(itemName, setName, have, total, bonuses)
  local t = { { left = itemName }, { left = "Soulbound" }, { left = "Head", right = "Mail" }, { left = "300 Armor" },
    { left = "+10 Agility" }, { left = "" }, { left = setName .. " (" .. have .. "/" .. total .. ")" },
    { left = "  Piece One" }, { left = "  Piece Two" }, { left = "" } }
  for _, b in ipairs(bonuses) do
    t[#t + 1] = { left = (have >= b[1]) and ("Set: " .. b[2]) or ("(" .. b[1] .. ") Set: " .. b[2]) }
  end
  return t
end

local GIANT = {
  { 3, "Improves your chance to hit by 1%." },
  { 3, "Increases the range of your Mend Pet spell by 50% and the effect by 10%." },
  { 5, "+40 Attack Power." },
  { 8, "Increases the damage of Multi-Shot by 15%." },
}

-- Hunter in 3 pieces of set 515 (helm, chest, legs).
local function giantClient(have)
  local cl = H.defaultClient()
  have = have or 3
  local slots = { 1, 5, 7, 3, 10 }
  for i = 1, have do
    local slot = slots[i]
    local id = 16840 + slot
    cl.items[slot] = { link = "|Hitem:" .. id .. ":0|h[Giantstalker " .. slot .. "]|h", setID = 515,
      stats = { ITEM_MOD_AGILITY_SHORT = 10 }, tip = setTip("Giantstalker " .. slot, "Giantstalker Armor", have, 8, GIANT) }
  end
  return cl
end

-- 1. Three pieces: hit bonus counted, Mend Pet bonus listed by number
do
  local h = H.boot({ client = giantClient(3) })
  local s = h.ns.Export()
  local F = h.ns.Decode(s)
  check("3pc: set field", F.set == "515:3", F.set)
  check("3pc: stat bonus summed", F.sb == "HIT:1", F.sb)
  check("3pc: other bonus by set:number", F.sbx == "515:2", F.sbx)
  check("3pc: inactive 5pc AP not counted", not (F.sb or ""):find("AP", 1, true), F.sb)
  check("3pc: nothing missing", F.miss == nil, F.miss)
  local notes = table.concat(h.ns.lastNotes, "|")
  check("3pc: note about the non-stat bonus", notes:find("1 active set bonus couldn't be turned into stats", 1, true), notes)
  check("3pc: no unreadable warning", not notes:find("Couldn't read your set", 1, true), notes)
  check("3pc: item stats unchanged by set bonus", F["is"]:find("AGI:41", 1, true), F["is"])
  check("3pc: field order sb before is", s:find("sb=", 1, true) < s:find("is=", 1, true))
  check("3pc: string still has no whitespace", not s:find("%s"), s)
end

-- 2. Eight pieces: all four active; dedupe means each bonus counts once
do
  local h = H.boot({ client = (function()
    local cl = giantClient(5)
    for _, slot in ipairs({ 6, 8, 9 }) do
      cl.items[slot] = { link = "|Hitem:" .. (16900 + slot) .. ":0|h[G]|h", setID = 515, stats = { ITEM_MOD_AGILITY_SHORT = 1 } }
    end
    for _, it in pairs(cl.items) do
      if it.setID == 515 then it.tip = setTip("G", "Giantstalker Armor", 8, 8, GIANT) end
    end
    return cl
  end)() })
  local F = h.ns.Decode(h.ns.Export())
  check("8pc: set count", F.set == "515:8", F.set)
  check("8pc: hit and AP once each", F.sb == "AP:40,HIT:1", F.sb)
  check("8pc: two other bonuses", F.sbx == "515:2,515:4", F.sbx)
  check("8pc: plural note", table.concat(h.ns.lastNotes, "|"):find("2 active set bonuses couldn't be turned into stats", 1, true),
    table.concat(h.ns.lastNotes, "|"))
end

-- 3. Two pieces of an 8-piece set: no bonus active yet, and that's not an error
do
  local h = H.boot({ client = giantClient(2) })
  local F = h.ns.Decode(h.ns.Export())
  check("2pc: no sb", F.sb == nil, F.sb)
  check("2pc: no sbx", F.sbx == nil, F.sbx)
  check("2pc: not missing", not (F.miss or ""):find("setbonus", 1, true), F.miss)
  check("2pc: no set notes", not table.concat(h.ns.lastNotes, "|"):find("set bonus", 1, true))
end

-- 4. Two different sets + all resistances + client stat template
do
  local cl = giantClient(3)
  local zg = { { 2, "+8 All Resistances." }, { 3, "+10 Agility." }, { 5, "+40 Attack Power when fighting Undead." } }
  cl.items[11] = { link = "|Hitem:19898:0|h[Ring]|h", setID = 480, stats = { ITEM_MOD_AGILITY_SHORT = 5 },
    tip = setTip("Ring", "Zandalar Signet", 3, 5, zg) }
  cl.items[13] = { link = "|Hitem:19899:0|h[Trinket]|h", setID = 480, stats = {}, tip = setTip("Trinket", "Zandalar Signet", 3, 5, zg) }
  cl.items[2] = { link = "|Hitem:19900:0|h[Neck]|h", setID = 480, stats = {}, tip = setTip("Neck", "Zandalar Signet", 3, 5, zg) }
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("two sets: both counted", F.set == "480:3,515:3", F.set)
  check("two sets: stats from both, resistances spread",
    F.sb == "AGI:10,ARCANE:8,FIRE:8,FROST:8,HIT:1,NATURE:8,SHADOW:8", F.sb)
  check("two sets: conditional bonus inactive -> not anywhere", not (F.sbx or ""):find("480", 1, true), F.sbx)
  -- Now make the conditional one active.
  for _, slot in ipairs({ 11, 13, 2 }) do cl.items[slot].tip = setTip("x", "Zandalar Signet", 5, 5, zg) end
  local F2 = H.boot({ client = cl }).ns
  local d2 = F2.Decode(F2.Export())
  check("conditional AP never counted as plain AP", not (d2.sb or ""):find("AP", 1, true), d2.sb)
  check("conditional AP listed as other", (d2.sbx or ""):find("480:3", 1, true), d2.sbx)
end

-- 5. Pieces whose tooltips can't be read: flagged once
do
  local cl = giantClient(3)
  for _, it in pairs(cl.items) do if it.setID then it.tip = nil end end
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("no set tooltips: missing setbonus once", F.miss and select(2, F.miss:gsub("setbonus", "")) == 1, F.miss)
  check("no set tooltips: warned", table.concat(h.ns.lastNotes, "|"):find("Couldn't read your set bonuses", 1, true))
end

-- 6. Client gives no set IDs: bonuses still read from the tooltip, set ID 0
do
  local cl = giantClient(3)
  for _, it in pairs(cl.items) do it.setID = nil end
  local h = H.boot({ client = cl })
  local F = h.ns.Decode(h.ns.Export())
  check("no set IDs: no set field", F.set == nil, F.set)
  check("no set IDs: stats still read", F.sb == "HIT:1", F.sb)
  check("no set IDs: other bonus with set 0", F.sbx == "0:2", F.sbx)
  check("no set IDs: read once (dedupe by name)", not (F.sbx or ""):find(",", 1, true), F.sbx)
end

-- 7. Secret tooltip text: nothing throws, bonuses flagged unreadable
do
  local cl = giantClient(3); cl.secret = { tip = true }
  local ok, s = pcall(function() return H.boot({ client = cl }).ns.Export() end)
  check("secret set tooltips don't throw", ok, s)
  local F = ok and H.boot().ns.Decode(s)
  check("secret set tooltips: setbonus missing", F and (F.miss or ""):find("setbonus", 1, true), F and F.miss)
end

-- 8. No set templates in the client: English fallbacks
do
  local h = H.boot({ client = giantClient(3), noSetTemplates = true })
  local F = h.ns.Decode(h.ns.Export())
  check("no set templates: still read", F.sb == "HIT:1" and F.sbx == "515:2", tostring(F.sb) .. " " .. tostring(F.sbx))
end

-- 9. German client: localized set strings and stat templates
do
  local cl = giantClient(0)
  local de = { { 2, "+10 Beweglichkeit." }, { 3, "Erhöht die Reichweite von Tier heilen." } }
  for _, slot in ipairs({ 1, 5, 7 }) do
    local t = { { left = "Teil" }, { left = "Riesenjäger (3/8)" }, { left = "" } }
    for _, b in ipairs(de) do t[#t + 1] = { left = "Set: " .. b[2] } end
    cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[x]|h", setID = 515, stats = {}, tip = t }
  end
  local h = H.boot({ client = cl, statGlobals = { ITEM_MOD_AGILITY = "%c%d Beweglichkeit" } })
  local F = h.ns.Decode(h.ns.Export())
  check("de: localized agility bonus", F.sb == "AGI:10", F.sb)
  check("de: other bonus listed", F.sbx == "515:2", F.sbx)
end

-- 10. ParseSetStat on its own
do
  local ns = H.boot().ns
  local P = ns.ParseSetStat
  local function one(text, key, v)
    local t = P(text)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    check("parse: " .. text, t and n == 1 and t[key] == v, t and (next(t)) .. "=" .. tostring(t[next(t)]))
  end
  one("Improves your chance to get a critical strike by 1%.", "CRIT", 1)
  one("Improves your chance to get a critical strike with spells by 1%.", "SCRIT", 1)
  one("Improves your chance to hit with spells by 2%.", "SHIT", 2)
  one("Increases damage and healing done by magical spells and effects by up to 23.", "SP", 23)
  one("Increases healing done by spells and effects by up to 44.", "HEAL", 44)
  one("Restores 4 mana per 5 sec.", "MP5", 4)
  one("+200 Armor.", "ARMOR", 200)
  one("+20 Ranged Attack Power.", "RAP", 20)
  one("Increases ranged attack power by 30.", "RAP", 30)
  one("Increases attack power by 40.", "AP", 40)
  one("+15 Stamina", "STA", 15)
  one("+12 Intellect.", "INT", 12)
  one("+10 Fire Resistance.", "FIRE", 10)
  one("Increases your chance to dodge an attack by 1%.", "DODGE", 1)
  one("Increases the block value of your shield by 30.", "BV", 30)
  one("Increased Defense +10.", "DEF", 10)
  one("  +10 Strength.  ", "STR", 10)
  one("-5 Spirit", "SPI", -5)
  check("parse: zero is not a bonus", P("+0 Agility") == nil)
  check("parse: proc text is not a stat", P("Chance on hit to heal you for 100.") == nil)
  check("parse: conditional is not a stat", P("+40 Attack Power when fighting Undead.") == nil)
  check("parse: nil safe", P(nil) == nil and P(42) == nil)
  check("parse: secret safe", pcall(P, H.SECRET) and P(H.SECRET) == nil)
end

-- 11. ParseSetTooltip on its own
do
  local ns = H.boot().ns
  local s = ns.ParseSetTooltip(setTip("Helm", "Giantstalker Armor", 3, 8, GIANT))
  check("tooltip: set name", s and s.name == "Giantstalker Armor", s and s.name)
  check("tooltip: have/total", s and s.have == 3 and s.total == 8)
  check("tooltip: 4 bonuses, 2 active", s and #s.bonuses == 4 and s.bonuses[1].active and s.bonuses[2].active
    and not s.bonuses[3].active and not s.bonuses[4].active)
  check("tooltip: non-set item -> nil", ns.ParseSetTooltip({ { left = "Ring" }, { left = "+5 Agility" } }) == nil)
  check("tooltip: item named like a set count on line 1 ignored",
    ns.ParseSetTooltip({ { left = "Thing (1/2)" }, { left = "Soulbound" } }) == nil)
  check("tooltip: nonsense count rejected", ns.ParseSetTooltip({ { left = "x" }, { left = "Y (9/2)" } }) == nil)
  check("tooltip: nil safe", ns.ParseSetTooltip(nil) == nil)
end

-- 12. TemplatePattern: %c and text captures
do
  local ns = H.boot().ns
  local p = ns.TemplatePattern("%c%d Agility")
  check("template %c: +", ("+10 Agility"):match(p) == "10", p)
  check("template %c: -", ("-3 Agility"):match(p) == "3", p)
  check("template %c: none", ("7 Agility"):match(p) == "7", p)
  local a, b, c = ("Giantstalker Armor (3/8)"):match(ns.TemplatePattern("%s (%d/%d)", true))
  check("template text capture", a == "Giantstalker Armor" and b == "3" and c == "8", tostring(a) .. tostring(b) .. tostring(c))
  check("template positional text", ("Set: x y"):match(ns.TemplatePattern("%1$s: %2$s", true)) == "Set")
end

-- 13. /simx check and debug show sets
do
  local h = H.boot({ client = giantClient(3) })
  local lines = table.concat(h.ns.CheckLines(), "\n")
  check("check: set line", lines:find("Set Giantstalker Armor (3/8, id 515): +1 HIT, 1 other bonus(es)", 1, true), lines)
  H.slash("debug")
  local text = h.ns.CopyFrame().text
  check("debug: set templates", text:find('Set templates: NAME "%s (%d/%d)"', 1, true), text)
  check("debug: set piece tooltip", text:find("Set piece in slot 1 (set 515):", 1, true)
    and text:find('"Set: Improves your chance to hit by 1%."', 1, true), text)
end

-- 14. Scanning-tooltip fallback reads sets too
do
  local h = H.boot({ client = giantClient(3), noTooltipInfo = true, scanTip = true })
  local F = h.ns.Decode(h.ns.Export())
  check("scan tooltip: set bonus read", F.sb == "HIT:1" and F.sbx == "515:2", tostring(F.sb) .. " " .. tostring(F.sbx))
end

-- 15. Deterministic with sets
do
  local a = H.boot({ client = giantClient(3) }).ns.Export()
  local b = H.boot({ client = giantClient(3) }).ns.Export()
  check("deterministic with sets", a == b)
end

-- Sample for the JS side
do
  local fh = io.open("./sample_sets.txt", "w")
  fh:write(H.boot({ client = giantClient(3) }).ns.Export())
  fh:close()
end

H.finish("SimBench sets")
