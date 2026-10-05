-- The export format is a contract with the Vulcan Sim, a separate website whose tests
-- run on sample exports copied from this add-on (its tools/refresh-fixtures.sh). Nothing
-- here can see the site, so this pins the layout instead. If any of these change, CI
-- fails until all three happen together:
--   1. bump ns.FORMAT in Util.lua (FSX1 -> FSX2) if strings change shape or meaning;
--   2. update CONTRACT below to match;
--   3. tell the sim's maintainers, so they update the decoder and refresh its fixtures.
package.path = "./?.lua;" .. package.path
local H = require("harness")

local CONTRACT = {
  FORMAT = "FSX1",
  FIELD_ORDER = { "v", "b", "d", "cls", "race", "fac", "lvl", "tal", "tr", "tn",
    "g", "w", "ammo", "qv", "set", "sb", "sbx", "is", "ie", "sh", "bs", "au", "miss" },
  SHEET_KEYS = { "str", "agi", "sta", "int", "spi", "ap", "rap", "crit", "rcrit", "scrit",
    "hit", "shit", "sp", "heal", "armor" },
  BASE_KEYS = { "str", "agi", "sta", "int", "spi", "ap", "rap" },
  -- The names inside fields: stat names in is/sb/ie (game key = exported name), and
  -- weapon location codes in g/w. Renaming one changes what a string means.
  STAT_NAMES = { "ITEM_MOD_AGILITY_SHORT=AGI", "ITEM_MOD_ATTACK_POWER_SHORT=AP", "ITEM_MOD_BLOCK_RATING_SHORT=BLOCK",
    "ITEM_MOD_BLOCK_VALUE_SHORT=BV", "ITEM_MOD_CRIT_MELEE_RATING_SHORT=CRIT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT=RCRIT",
    "ITEM_MOD_CRIT_RATING_SHORT=CRIT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT=SCRIT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT=DEF",
    "ITEM_MOD_DODGE_RATING_SHORT=DODGE", "ITEM_MOD_HEALTH_REGEN_SHORT=HP5", "ITEM_MOD_HIT_MELEE_RATING_SHORT=HIT",
    "ITEM_MOD_HIT_RANGED_RATING_SHORT=RHIT", "ITEM_MOD_HIT_RATING_SHORT=HIT", "ITEM_MOD_HIT_SPELL_RATING_SHORT=SHIT",
    "ITEM_MOD_INTELLECT_SHORT=INT", "ITEM_MOD_MANA_REGENERATION_SHORT=MP5", "ITEM_MOD_PARRY_RATING_SHORT=PARRY",
    "ITEM_MOD_POWER_REGEN0_SHORT=MP5", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT=RAP", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=SP",
    "ITEM_MOD_SPELL_HEALING_DONE_SHORT=HEAL", "ITEM_MOD_SPELL_POWER_SHORT=SP", "ITEM_MOD_SPIRIT_SHORT=SPI",
    "ITEM_MOD_STAMINA_SHORT=STA", "ITEM_MOD_STRENGTH_SHORT=STR", "RESISTANCE0_NAME=ARMOR", "RESISTANCE2_NAME=FIRE",
    "RESISTANCE3_NAME=NATURE", "RESISTANCE4_NAME=FROST", "RESISTANCE5_NAME=SHADOW", "RESISTANCE6_NAME=ARCANE" },
  LOC_CODES = { "INVTYPE_2HWEAPON=2H", "INVTYPE_HOLDABLE=HO", "INVTYPE_RANGED=RG", "INVTYPE_RANGEDRIGHT=RG",
    "INVTYPE_RELIC=RL", "INVTYPE_SHIELD=SH", "INVTYPE_THROWN=TH", "INVTYPE_WEAPON=1H", "INVTYPE_WEAPONMAINHAND=MH",
    "INVTYPE_WEAPONOFFHAND=OH" },
}
local function pairsList(t)
  local o = {}
  for k, v in pairs(t or {}) do o[#o + 1] = k .. "=" .. v end
  table.sort(o)
  return table.concat(o, ",")
end
local MSG = "the export layout changed: bump ns.FORMAT, update tests_format_contract.lua, and tell the Vulcan Sim"

local ns = H.boot().ns
H.check("format version is " .. CONTRACT.FORMAT .. " (" .. MSG .. ")", ns.FORMAT == CONTRACT.FORMAT, ns.FORMAT)
for _, name in ipairs({ "FIELD_ORDER", "SHEET_KEYS", "BASE_KEYS" }) do
  local got = table.concat(ns[name] or {}, ",")
  H.check(name .. " unchanged (" .. MSG .. ")", got == table.concat(CONTRACT[name], ","), got)
end
for _, name in ipairs({ "STAT_NAMES", "LOC_CODES" }) do
  local got = pairsList(ns[name])
  H.check(name .. " unchanged (" .. MSG .. ")", got == table.concat(CONTRACT[name], ","), got)
end
-- Every key a real export writes is one the contract names.
local s = ns.Export()
local known = {}
for _, k in ipairs(CONTRACT.FIELD_ORDER) do known[k] = true end
local unknown = {}
for k in (s:match("^FSX%d+:(.-)#") or ""):gmatch("([%w_]+)=") do
  if not known[k] then unknown[#unknown + 1] = k end
end
H.check("an export writes only contract fields", s:find("^" .. CONTRACT.FORMAT .. ":") ~= nil and #unknown == 0, table.concat(unknown, ","))
-- ...and only the contract's stat names and weapon codes inside them.
local stats, locs = {}, {}
for _, kv in ipairs(CONTRACT.STAT_NAMES) do stats[kv:match("=(.+)$")] = true end
for _, kv in ipairs(CONTRACT.LOC_CODES) do locs[kv:match("=(.+)$")] = true end
-- Set bonuses (sb) and item extras (ie) get their stat names from tooltip wording
-- (ns.SET_STAT_PATTERNS) and the client's stat strings (ns.SET_STAT_GLOBALS), not from
-- STAT_NAMES. Every name they can produce must still be a contract stat name.
local outside, nTargets = {}, 0
for _, list in ipairs({ ns.SET_STAT_PATTERNS or {}, ns.SET_STAT_GLOBALS or {} }) do
  for _, p in ipairs(list) do
    for _, k in ipairs(type(p[2]) == "table" and p[2] or { p[2] }) do
      nTargets = nTargets + 1
      if not stats[k] then outside[#outside + 1] = tostring(k) end
    end
  end
end
H.check("set-bonus and tooltip stat names are all contract stat names (" .. MSG .. ")",
  #(ns.SET_STAT_PATTERNS or {}) > 0 and #(ns.SET_STAT_GLOBALS or {}) > 0 and nTargets > 0 and #outside == 0,
  table.concat(outside, ","))
local odd = {}
for _, field in ipairs({ "is", "sb", "ie" }) do
  local v = s:match("[:;]" .. field .. "=([^;#]*)")
  for k in (v or ""):gmatch("([%u%d]+):") do
    if not stats[k] then odd[#odd + 1] = field .. ":" .. k end
  end
end
for _, field in ipairs({ "g", "w" }) do
  local v = s:match("[:;]" .. field .. "=([^;#]*)")
  for item in (v or ""):gmatch("[^,]+") do
    local loc = item:match(":(%u[%u%d]*)$") or item:match(":(%d[HD])$")
    if loc and not locs[loc] then odd[#odd + 1] = field .. ":" .. loc end
  end
end
H.check("an export uses only contract stat names and weapon codes", #odd == 0 and s:find("is=", 1, true) ~= nil and s:find(":2H", 1, true) ~= nil, table.concat(odd, ","))

H.finish("SimBench format contract")
