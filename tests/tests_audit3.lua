-- Regression tests for audit round 3: non-English clients, fresh-login advice,
-- placeholder tooltips, new stat wording, protected /simx check, paste box focus.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check

local function export(opts)
  local h = H.boot(opts)
  local s = h.ns.Export()
  return h.ns.Decode(s), h, s
end
local function notes(h) return table.concat(h.ns.lastNotes or {}, "|") end

-- 1. Non-English client: unread Equip/set text gets an honest note
do
  local cl = H.defaultClient()
  cl.items[1].tip = { { left = "Helm" }, { left = "Equip: Verbessert Eure Trefferchance um 1%." } }
  local F, h = export({ client = cl, locale = "deDE" })
  check("deDE + unread Equip line: locale flagged", (F.miss or ""):find("locale", 1, true), F.miss)
  check("deDE: honest note", notes(h):find("isn't in English", 1, true), notes(h))
  local F2 = export({ client = cl })
  check("enUS: same text is just a non-stat line", not (F2.miss or ""):find("locale", 1, true), F2.miss)
  local F3 = export({ locale = "deDE" })
  check("deDE with nothing unread: no flag", not (F3.miss or ""):find("locale", 1, true), F3.miss)
  local lines = table.concat(H.boot({ client = cl, locale = "deDE" }).ns.CheckLines(), "\n")
  check("/simx check shows the language", lines:find("Game language: deDE", 1, true), lines)
end
do  -- set bonus in another language
  local cl = H.defaultClient()
  local tip = { { left = "x" }, { left = "Riesenjäger (2/8)" }, { left = "Set: Verbessert Eure Trefferchance um 1%." } }
  for _, slot in ipairs({ 1, 5 }) do cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = {}, tip = tip } end
  local F, h = export({ client = cl, locale = "deDE" })
  check("deDE set bonus: listed and flagged", F.sbx == "515:1" and (F.miss or ""):find("locale", 1, true), tostring(F.sbx) .. " " .. tostring(F.miss))
  check("set note doesn't claim it's a proc", notes(h):find("couldn't be turned into stats", 1, true), notes(h))
end

-- 2. Fresh login: a weapon that hadn't loaded gets "export again" advice
do
  local cl = H.defaultClient()
  cl.items[16].uncached = true; cl.items[16].tip = { { left = "Retrieving item information" } }
  local F, h = export({ client = cl })
  check("unloaded weapon: missing", (F.miss or ""):find("weapon16", 1, true), F.miss)
  check("unloaded weapon: export again advice", notes(h):find("(Main Hand) because it hadn't loaded yet", 1, true), notes(h))
  check("unloaded weapon: no debug advice for it", not notes(h):find("(Main Hand). Export again; if it keeps", 1, true), notes(h))
  local cl2 = H.defaultClient(); cl2.items[16].tip = { { left = "Axe" } }
  local _, h2 = export({ client = cl2 })
  check("loaded but unreadable weapon: debug advice", notes(h2):find("if it keeps happening, type /simx debug", 1, true), notes(h2))
end

-- 3. "Retrieving item information" placeholder: set read as unreadable, not unrecognised
do
  local cl = H.defaultClient()
  for _, slot in ipairs({ 1, 5 }) do
    cl.items[slot] = { link = "|Hitem:" .. (16840 + slot) .. ":0|h[G]|h", setID = 515, stats = {},
      tip = { { left = "Retrieving item information" } } }
  end
  local F = export({ client = cl })
  check("placeholder tooltip -> setbonus (try again)", (F.miss or ""):find("setbonus", 1, true)
    and not (F.miss or ""):find("setparse", 1, true), F.miss)
  local ns = H.boot().ns
  check("TooltipLoaded", ns.TooltipLoaded({ { left = "Helm" } }) and not ns.TooltipLoaded({ { left = "Retrieving item information" } })
    and not ns.TooltipLoaded({}) and not ns.TooltipLoaded(nil))
end

-- 4. New stat wording
do
  local P = H.boot().ns.ParseSetStat
  local function one(text, key, v) local t = P(text); check("parse: " .. text, t and t[key] == v, t and next(t)) end
  one("Increases your chance to parry an attack by 1%.", "PARRY", 1)
  one("Increases your chance to block attacks with a shield by 2%.", "BLOCK", 2)
  one("Improves your chance to get a critical strike with missile weapons by 1%.", "RCRIT", 1)
  one("Improves your chance to hit with missile weapons by 1%.", "RHIT", 1)
end

-- 5. /simx check survives an unexpected error
do
  local h = H.boot()
  h.ns.CollectAll = function() error("surprise") end
  local ok, lines = pcall(h.ns.CheckLines)
  check("check: no Lua error escapes", ok, lines)
  check("check: plain message", ok and table.concat(lines, "\n"):find("The check hit an error", 1, true), ok and table.concat(lines, "|"))
end

-- 6. Paste box: a click in the scroll area focuses the box
do
  local h = H.boot()
  H.slash("verify")
  local scroll, box
  for _, fr in ipairs(h.c.frames) do
    if fr.kind == "ScrollFrame" then scroll = fr end
    if fr.kind == "EditBox" then box = fr end
  end
  box.focused = false
  scroll.scripts.OnMouseDown(scroll)
  check("click in scroll area focuses the box", box.focused == true)
end

H.finish("SimBench audit 3")
