-- Writes Lua-made strings for the JS decoder to verify (cross-language checks).
package.path = "./?.lua;" .. package.path
local H = require("harness")
local out = {}
do  -- German tree names (UTF-8), decimal commas
  local cl = H.defaultClient()
  cl.talents[3].name = "Überleben"
  cl.items[16].tip = { { left = "X" }, { left = "153 - 256 Schaden", right = "Tempo 3,80" } }
  local h = H.boot({ client = cl, damageTemplate = "%s - %s Schaden" })
  out[#out + 1] = "de\t" .. h.ns.Export()
end
do  -- Warrior with sword and shield, no quiver/ammo
  local cl = H.defaultClient()
  cl.class = "WARRIOR"; cl.ammo = nil; cl.bags = {}
  cl.items[18] = nil
  cl.items[16] = { link = "|Hitem:810:0|h[S]|h", loc = "INVTYPE_WEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 5 },
    tip = { { left = "S" }, { left = "59 - 110 Damage", right = "Speed 2.40" } } }
  cl.items[17] = { link = "|Hitem:12602:0|h[D]|h", loc = "INVTYPE_SHIELD", stats = { RESISTANCE0_NAME = 2500 } }
  out[#out + 1] = "warshield\t" .. H.boot({ client = cl }).ns.Export()
end
do  -- secrets everywhere except class/level
  local cl = H.defaultClient()
  cl.secret = { crit = true, ap = true, stat = true, rank = true, aura = true, tip = true, link = true }
  out[#out + 1] = "secret\t" .. H.boot({ client = cl }).ns.Export()
end
do  -- tree name with a non-breaking space (and a zero-width space)
  local cl = H.defaultClient()
  cl.talents[1].name = "Beast\194\160Mastery\226\128\139"
  out[#out + 1] = "nbsp\t" .. H.boot({ client = cl }).ns.Export()
end
do  -- hit only in "Equip:" text
  local cl = H.defaultClient()
  cl.items[1].tip = { { left = "Helm" }, { left = "Equip: Improves your chance to hit by 1%." } }
  out[#out + 1] = "equip\t" .. H.boot({ client = cl }).ns.Export()
end
do  -- Forever client with only points per tree (no tr field)
  out[#out + 1] = "forever\t" .. H.boot({ forever = true, noTalentInfo = true }).ns.Export()
end
-- Paste corpus: the in-game decoder's verdict on each paste, for the JS
-- decoder to match (both must agree on what verifies). Hex-encoded, one per line.
do
  local ns = H.boot().ns
  local S = ns.Export()
  local function signed(body) return body .. "#" .. ns.Adler32(body) end
  local pastes = {
    S, "my hunter: " .. S .. " thanks", "FSX string for my hunter: " .. S, S .. "\n" .. S,
    S:sub(1, 200) .. "\n" .. S, S .. " see #deadbeef", S:sub(1, -3), (S:gsub("lvl=60", "lvl=61")),
    S:sub(1, -9) .. S:sub(-8):upper(), "```\n" .. S .. "\n```", S:sub(1, 40) .. "\194\160\226\128\139" .. S:sub(41),
    signed("FSX2:a=1"), signed("FSX2:a=1") .. " " .. S, signed("FSX0:a=1"), "hello", "",
    ("\195\169"):rep(40000) .. S, ("\195\169"):rep(1000) .. S, ("FSX1:#00000000"):rep(50) .. S,
    ("FSX1:"):rep(9) .. S, signed("FSX1:cls=ROGUE;tn=\195\156berleben"),
  }
  local fc = io.open("./cross_corpus.txt", "w")
  for _, p in ipairs(pastes) do
    local ok = ns.Decode(p) ~= nil
    fc:write((ok and "ok" or "err") .. "\t" .. (p:gsub(".", function(c) return string.format("%02x", c:byte()) end)) .. "\n")
  end
  fc:close()
  out[#out + 1] = "corpus\t" .. #pastes
end
-- One real export per class, for the sim's import test (every class must import).
do
  local fc = io.open("./cross_classes.txt", "w")
  local n = 0
  for _, cls in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    local cl = H.defaultClient()
    cl.class = cls
    local s = H.boot({ client = cl }).ns.Export()
    if s and s:find("cls=" .. cls, 1, true) then
      fc:write(cls:lower() .. "\t" .. s .. "\n")
      n = n + 1
    end
  end
  fc:close()
  H.check("an export for every class", n == 9, n)
end
local fh = io.open("./cross_samples.txt", "w")
fh:write(table.concat(out, "\n"))
fh:close()
H.check("wrote samples", #out == 7)
H.finish("SimBench cross (Lua side)")
