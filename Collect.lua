-- SimBench: reads the character. Everything here runs out of combat only;
-- in combat Forever turns most of these values secret.
local _, ns = ...

ns.SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
ns.AMMO_SLOT = 0
ns.WEAPON_SLOTS = { 16, 17, 18 }
ns.QUIVER_CLASS_ID = 11   -- item class "Quiver" (quivers and ammo pouches)

-- GetItemStats keys -> short names used in the string. Unknown keys are kept
-- (shortened) so new Forever stats show up instead of vanishing.
ns.STAT_NAMES = {
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
  ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
  ITEM_MOD_CRIT_RANGED_RATING_SHORT = "RCRIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SCRIT",
  ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
  ITEM_MOD_HIT_RANGED_RATING_SHORT = "RHIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "SHIT",
  ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
  ITEM_MOD_POWER_REGEN0_SHORT = "MP5", ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
  RESISTANCE0_NAME = "ARMOR", ITEM_MOD_BLOCK_VALUE_SHORT = "BV", ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
  RESISTANCE2_NAME = "FIRE", RESISTANCE3_NAME = "NATURE", RESISTANCE4_NAME = "FROST",
  RESISTANCE5_NAME = "SHADOW", RESISTANCE6_NAME = "ARCANE",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
  ITEM_MOD_PARRY_RATING_SHORT = "PARRY", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
}
-- Weapon DPS is derived from damage and speed, which are exported separately.
ns.STAT_SKIP = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = true }

-- Equip locations -> short codes. Weapons get their damage read; a shield or
-- held-in-off-hand item in slot 17 is recorded but has no damage to read.
ns.LOC_CODES = {
  INVTYPE_2HWEAPON = "2H", INVTYPE_WEAPON = "1H", INVTYPE_WEAPONMAINHAND = "MH",
  INVTYPE_WEAPONOFFHAND = "OH", INVTYPE_RANGED = "RG", INVTYPE_RANGEDRIGHT = "RG",
  INVTYPE_THROWN = "TH", INVTYPE_SHIELD = "SH", INVTYPE_HOLDABLE = "HO", INVTYPE_RELIC = "RL",
}
ns.DAMAGE_LOCS = { ["2H"] = true, ["1H"] = true, MH = true, OH = true, RG = true, TH = true }
-- Slots that never carry stats worth reading (shirt, tabard).
ns.NO_STAT_SLOTS = { [4] = true, [19] = true }
-- Slot names for messages (players don't know slot numbers).
ns.SLOT_NAMES = { [0] = "Ammo", "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist",
  "Hands", "Ring 1", "Ring 2", "Trinket 1", "Trinket 2", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
local function SlotList(slots)
  local names = {}
  for i, slot in ipairs(slots) do names[i] = ns.SLOT_NAMES[tonumber(slot)] or ("slot " .. slot) end
  return table.concat(names, ", ")
end
ns.SlotList = SlotList

local function GetInstant(id)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  return ns.try(fn, id)
end

-- Equip-location code for an item ID ("2H", "SH", ...), or nil.
function ns.LocCode(id)
  local loc = ns.str(select(4, GetInstant(id)))
  return loc and ns.LOC_CODES[loc] or nil
end

function ns.StatName(key)
  if ns.STAT_NAMES[key] then return ns.STAT_NAMES[key] end
  local short = key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")
  return ns.clean(short)
end

---------------------------------------------------------------------------
-- Combat check
---------------------------------------------------------------------------
function ns.InCombat()
  local lock = ns.try(InCombatLockdown)
  if ns.IsSecret(lock) or lock then return true end
  local aff = ns.try(UnitAffectingCombat, "player")
  if ns.IsSecret(aff) or aff then return true end
  return false
end

---------------------------------------------------------------------------
-- Tooltip text. Returns a list of { left =, right = } with plain strings.
---------------------------------------------------------------------------
local scanTip
local function ScanTip()
  if scanTip then return scanTip end
  if not CreateFrame then return nil end
  local ok, tip = pcall(CreateFrame, "GameTooltip", "VulcanSimBenchScanTip", nil, "GameTooltipTemplate")
  if not ok or not tip then return nil end
  scanTip = tip
  return tip
end

local function LinesFromData(data)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local out = {}
  for _, l in ipairs(data.lines) do
    if type(l) == "table" then
      out[#out + 1] = { left = ns.StripCodes(l.leftText), right = ns.StripCodes(l.rightText) }
    end
  end
  return out
end

-- kind = "inv" (slot) or "item" (item ID). During an export the result is
-- cached (ns.tipCache), since set bonuses, equip effects and weapon damage
-- all read the same tooltips.
function ns.TooltipLines(kind, arg)
  local key = kind .. ":" .. tostring(arg)
  if ns.tipCache and ns.tipCache[key] ~= nil then return ns.tipCache[key] or nil end
  local lines = ns.ReadTooltip(kind, arg)
  if ns.tipCache then ns.tipCache[key] = lines or false end
  return lines
end

function ns.ReadTooltip(kind, arg)
  local TI = C_TooltipInfo
  if TI then
    local data
    if kind == "inv" then data = ns.try(TI.GetInventoryItem, "player", arg)
    else data = ns.try(TI.GetItemByID, arg) end
    local lines = LinesFromData(data)
    if lines and #lines > 0 then return lines end
  end
  local tip = ScanTip()
  if not tip then return nil end
  ns.try(tip.SetOwner, tip, WorldFrame or UIParent, "ANCHOR_NONE")
  ns.try(tip.ClearLines, tip)
  if kind == "inv" then ns.try(tip.SetInventoryItem, tip, "player", arg)
  else ns.try(tip.SetItemByID, tip, arg) end
  local n = ns.num(ns.try(tip.NumLines, tip)) or 0
  local out = {}
  for i = 1, n do
    local L, R = _G["VulcanSimBenchScanTipTextLeft" .. i], _G["VulcanSimBenchScanTipTextRight" .. i]
    local left = L and ns.StripCodes(ns.try(L.GetText, L))
    -- A hidden right-hand line can still hold text from an earlier tooltip.
    local right = R and ns.try(R.IsShown, R) and ns.StripCodes(ns.try(R.GetText, R)) or nil
    if left or right then out[#out + 1] = { left = left, right = right } end
  end
  ns.try(tip.Hide, tip)
  return #out > 0 and out or nil
end

---------------------------------------------------------------------------
-- Tooltip parsers (pure functions; tested directly).
---------------------------------------------------------------------------
local GENERIC_RANGE = "^%s*([%d%.,]+)%s*%-%s*([%d%.,]+)%s"
local GENERIC_DECIMAL = "(%d+[%.,]%d+)"

-- Weapon base damage and speed: { min =, max =, speed = } or nil.
function ns.ParseWeapon(lines)
  if type(lines) ~= "table" then return nil end
  local pat = ns.TemplatePattern(DAMAGE_TEMPLATE)
  local single = ns.TemplatePattern(SINGLE_DAMAGE_TEMPLATE)   -- "%s Damage" (min = max)
  local lo, hi, speed
  for _, l in ipairs(lines) do
    local left = l.left
    -- Skip bonus-damage lines ("+5 - 10 Fire Damage"): they start with "+".
    if left and not left:find("^%s*%+") then
      local a, b
      if pat then a, b = left:match(pat) end
      if not a then a, b = left:match(GENERIC_RANGE) end
      if not a and single then
        a = left:match(single)
        b = a
      end
      if a and b then
        lo, hi = ns.ToNumber(a), ns.ToNumber(b)
        if l.right then speed = ns.ToNumber(l.right:match(GENERIC_DECIMAL)) end
        break
      end
    end
  end
  if lo and hi and not speed then
    -- Some layouts put speed on its own line.
    for _, l in ipairs(lines) do
      local r = l.right or ""
      local s = r:match(GENERIC_DECIMAL)
      if s then speed = ns.ToNumber(s); break end
    end
  end
  if not (lo and hi and speed) or speed <= 0 or hi <= 0 or hi < lo then return nil end
  return { min = lo, max = hi, speed = speed }
end

-- Ammo damage per second ("Adds 13.0 damage per second"), or nil.
function ns.ParseAmmo(lines)
  if type(lines) ~= "table" then return nil end
  local pat = ns.TemplatePattern(AMMO_DAMAGE_TEMPLATE)
  for _, l in ipairs(lines) do
    local left = l.left
    if left then
      local v
      if pat then v = left:match(pat) end
      if not v and left:lower():find("damage per second", 1, true) then v = left:match("([%d%.,]+)") end
      if v then return ns.ToNumber(v) end
    end
  end
  return nil
end

-- Quiver haste percent ("Increases ranged attack speed by 13%."), or nil.
-- Prefers the line that mentions attack speed (English); otherwise the first
-- percent after the bag's name, which is the only one on a plain quiver.
function ns.ParseQuiver(lines)
  if type(lines) ~= "table" then return nil end
  local first
  for i = 2, #lines do   -- line 1 is the bag's name
    local left = lines[i].left
    local v = left and left:match("(%d+[%.,]?%d*)[%s\194\160]*%%")   -- French puts a (no-break) space before %
    if v then
      if left:lower():find("attack speed", 1, true) then return ns.ToNumber(v) end
      first = first or v
    end
  end
  return first and ns.ToNumber(first) or nil
end

---------------------------------------------------------------------------
-- Pieces of the export
---------------------------------------------------------------------------
local function GetStatsTable(link)
  local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
  local t = ns.try(fn, link)
  if type(t) ~= "table" then
    -- Older signature: GetItemStats(link, tableToFill)
    local fill = {}
    ns.try(fn, link, fill)
    if next(fill) then t = fill end
  end
  return type(t) == "table" and t or nil
end

-- True if an equipped item's tooltip has a plain stat or armor line.
local function TooltipShowsStats(slot)
  local armor = ns.TemplatePattern(ARMOR_TEMPLATE) or "^%s*([%d%.,]+) Armor%s*$"
  for i, l in ipairs(ns.TooltipLines("inv", slot) or {}) do
    local left = l.left
    -- "+20 Agility" or "300 Armor"; not a weapon's "+5 - 10 Fire Damage".
    local stat = left and left:find("^%s*[%+%-]%d") and not left:find("^%s*%+%s*[%d%.,]+%s*%-%s*%d")
    if i > 1 and left and (stat or left:match(armor)) then return true end
  end
  return false
end

local function ParseLink(link)
  link = ns.str(link)
  if not link then return nil end
  local id, ench = link:match("item:(%d+):?(%d*)")
  return tonumber(id), tonumber(ench) or 0
end

-- Equipped items, summed item stats, weapon damage. Fills data and missing.
function ns.CollectGear(data, missing)
  data.gear, data.itemStats, data.weapons, data.perItem, data.sets = {}, {}, {}, {}, {}
  local statsRead, unread = 0, {}
  for _, slot in ipairs(ns.SLOTS) do
    local link = ns.str(ns.try(GetInventoryItemLink, "player", slot))
    local id, ench = ParseLink(link)
    if not id then id = ns.num(ns.try(GetInventoryItemID, "player", slot)) end
    if id then
      local entry = { slot = slot, id = id, ench = ench or 0 }
      if slot >= 16 and slot <= 18 then entry.loc = ns.LocCode(id) end
      data.gear[#data.gear + 1] = entry
      local stats = link and GetStatsTable(link)
      -- GetItemInfo is nil until the client has the item's data; its stats may
      -- then come back empty, which must not pass for "no stats".
      local infoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
      local info = link and { ns.try(infoFn, link) } or {}
      -- Without an item-info function there's no way to tell; assume loaded.
      local cached = ns.str(info[1]) ~= nil or (link ~= nil and type(infoFn) ~= "function")
      if not cached then
        ns.try(C_Item and C_Item.RequestLoadItemDataByID, id)
        entry.notLoaded = true
      end
      if stats and not cached and not next(stats) then stats = nil end
      -- An empty table for a loaded item is trusted only if the tooltip agrees.
      if stats and cached and not next(stats) and TooltipShowsStats(slot) then stats = nil end
      -- A loaded item with no stats at all (a plain trinket) is read, not
      -- missing, unless its tooltip shows stats ("+20 Agility", "300 Armor").
      local statsFn = (C_Item and C_Item.GetItemStats) or GetItemStats
      if not stats and cached and type(statsFn) == "function" and not TooltipShowsStats(slot) then stats = {} end
      if not stats and not ns.NO_STAT_SLOTS[slot] then unread[#unread + 1] = slot end
      if stats then
        -- A shirt or tabard reading fine says nothing about the real gear.
        if not ns.NO_STAT_SLOTS[slot] then statsRead = statsRead + 1 end
        -- Two game keys can mean one stat (ITEM_MOD_HIT_RATING_SHORT and
        -- ITEM_MOD_HIT_MELEE_RATING_SHORT): within one item keep the larger,
        -- never the sum. Unknown keys are noted so "Equip:" text can't double them.
        local mine, unknown = {}, false
        for k, v in pairs(stats) do
          v = ns.num(v)
          if v and type(k) == "string" and not ns.STAT_SKIP[k] and v ~= 0 then
            local name = ns.StatName(k)
            if name and name ~= "" then
              if not ns.STAT_NAMES[k] then unknown = true end
              if mine[name] == nil or math.abs(v) > math.abs(mine[name]) then mine[name] = v end
            end
          end
        end
        for name, v in pairs(mine) do data.itemStats[name] = (data.itemStats[name] or 0) + v end
        data.perItem[slot] = mine
        if unknown then data.unknownStatSlots = data.unknownStatSlots or {}; data.unknownStatSlots[slot] = true end
      end
      -- Set pieces (setID is GetItemInfo's 16th value). Set bonuses are read
      -- from the tooltip in CollectSetBonuses.
      local setID = ns.num(info[16])
      if setID and setID > 0 then
        data.sets[setID] = (data.sets[setID] or 0) + 1
        entry.set = setID
      end
    end
  end
  local realItems = 0
  for _, g in ipairs(data.gear) do if not ns.NO_STAT_SLOTS[g.slot] then realItems = realItems + 1 end end
  if realItems > 0 and statsRead == 0 then
    missing[#missing + 1] = "itemstats"
    -- Usually a fresh login: say so, so the player knows exporting again fixes it.
    for _, g in ipairs(data.gear) do
      if g.notLoaded then missing[#missing + 1] = "notloaded"; break end
    end
  else
    -- Some items readable, some not: the totals would be short, so say which.
    for _, slot in ipairs(unread) do missing[#missing + 1] = "itemstats" .. slot end
  end

  for _, g in ipairs(data.gear) do
    -- Unknown location (item data not loaded yet): try anyway; a shield simply
    -- has no damage line, and only a real weapon is reported missing.
    if g.slot >= 16 and g.slot <= 18 and (g.loc == nil or ns.DAMAGE_LOCS[g.loc]) then
      local w = ns.ParseWeapon(ns.TooltipLines("inv", g.slot))
      if w then
        w.loc = g.loc
        data.weapons[g.slot] = w
      elseif g.loc or g.notLoaded or g.slot == 16 then
        -- Type unknown and not loaded: it may be a weapon, so say it's missing.
        -- The main hand always holds a weapon, so no damage there is always news.
        missing[#missing + 1] = "weapon" .. g.slot
      end
    end
  end

  -- Ammo (Hunters): slot 0 on clients that still have it.
  local ammoID = ns.num(ns.try(GetInventoryItemID, "player", ns.AMMO_SLOT))
  if ammoID then
    data.gear[#data.gear + 1] = { slot = ns.AMMO_SLOT, id = ammoID, ench = 0 }
    data.ammoDps = ns.ParseAmmo(ns.TooltipLines("item", ammoID))
    if not data.ammoDps then missing[#missing + 1] = "ammo" end
  end
end

-- Quiver or ammo pouch in the bag slots: its ranged haste percent.
function ns.CollectQuiver(data, missing)
  for bag = 1, 4 do
    local inv = C_Container and ns.num(ns.try(C_Container.ContainerIDToInventoryID, bag))
    inv = inv or (ns.num(ns.try(ContainerIDToInventoryID, bag))) or (19 + bag)
    local id = ns.num(ns.try(GetInventoryItemID, "player", inv))
    if id then
      local classID = ns.num(select(6, GetInstant(id)))
      if classID == ns.QUIVER_CLASS_ID then
        data.quiverHaste = ns.ParseQuiver(ns.TooltipLines("inv", inv))
        if not data.quiverHaste then missing[#missing + 1] = "quiver" end
        return
      end
    end
  end
end

---------------------------------------------------------------------------
-- Set bonuses. A set piece's tooltip lists every bonus of its set: active ones
-- as "Set: <text>", inactive ones as "(4) Set: <text>". Active bonuses that are
-- plain stats are summed; the rest (procs, ability changes) are listed by
-- set ID and bonus number so the sim can model the ones it knows.
---------------------------------------------------------------------------
local RESISTS = { "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }

-- English wording of stat bonuses, matched against lowercased text with the
-- final period removed. Anchored at both ends so a conditional bonus ("+40
-- Attack Power when fighting Undead") is never counted as a plain stat.
local N = "(%d+[%.,]?%d*)"
ns.SET_STAT_PATTERNS = {
  { "^%+" .. N .. " ranged attack power$", "RAP" },
  { "^increases ranged attack power by " .. N .. "$", "RAP" },
  { "^%+" .. N .. " attack power$", "AP" },
  { "^increases attack power by " .. N .. "$", "AP" },
  { "^improves your chance to hit with spells by " .. N .. "%%$", "SHIT" },
  { "^improves your chance to hit by " .. N .. "%%$", "HIT" },
  { "^increases your chance to hit by " .. N .. "%%$", "HIT" },
  { "^improves your chance to get a critical strike with spells by " .. N .. "%%$", "SCRIT" },
  { "^improves your chance to get a critical strike by " .. N .. "%%$", "CRIT" },
  { "^increases damage and healing done by magical spells and effects by up to " .. N .. "$", "SP" },
  { "^increases healing done by spells and effects by up to " .. N .. "$", "HEAL" },
  { "^restores " .. N .. " mana per 5 sec$", "MP5" },
  { "^restores " .. N .. " health per 5 sec$", "HP5" },
  { "^restores " .. N .. " health every 5 sec$", "HP5" },
  { "^%+" .. N .. " armor$", "ARMOR" },
  { "^%+" .. N .. " strength$", "STR" },
  { "^%+" .. N .. " agility$", "AGI" },
  { "^%+" .. N .. " stamina$", "STA" },
  { "^%+" .. N .. " intellect$", "INT" },
  { "^%+" .. N .. " spirit$", "SPI" },
  { "^%+" .. N .. " to all resistances$", RESISTS },
  { "^%+" .. N .. " all resistances$", RESISTS },
  { "^%+" .. N .. " fire resistance$", "FIRE" },
  { "^%+" .. N .. " nature resistance$", "NATURE" },
  { "^%+" .. N .. " frost resistance$", "FROST" },
  { "^%+" .. N .. " shadow resistance$", "SHADOW" },
  { "^%+" .. N .. " arcane resistance$", "ARCANE" },
  { "^increases your chance to dodge an attack by " .. N .. "%%$", "DODGE" },
  { "^increases your chance to parry an attack by " .. N .. "%%$", "PARRY" },
  { "^increases your chance to block attacks with a shield by " .. N .. "%%$", "BLOCK" },
  { "^improves your chance to get a critical strike with missile weapons by " .. N .. "%%$", "RCRIT" },
  { "^improves your chance to hit with missile weapons by " .. N .. "%%$", "RHIT" },
  { "^increases the block value of your shield by " .. N .. "$", "BV" },
  { "^increased defense %+" .. N .. "$", "DEF" },
  { "^%+" .. N .. " defense$", "DEF" },
}
-- The client's own (localized) stat strings, tried first: "%c%d Agility" etc.
ns.SET_STAT_GLOBALS = {
  { "ITEM_MOD_STRENGTH", "STR" }, { "ITEM_MOD_AGILITY", "AGI" }, { "ITEM_MOD_STAMINA", "STA" },
  { "ITEM_MOD_INTELLECT", "INT" }, { "ITEM_MOD_SPIRIT", "SPI" },
  { "ITEM_MOD_ATTACK_POWER", "AP" }, { "ITEM_MOD_RANGED_ATTACK_POWER", "RAP" },
  { "ITEM_MOD_MANA_REGENERATION", "MP5" }, { "ITEM_RESIST_ALL", RESISTS },
}
local SET_STAT_GLOBALS = ns.SET_STAT_GLOBALS

-- One bonus's text -> { STAT = value, ... }, or nil if it isn't a plain stat.
function ns.ParseSetStat(text)
  text = ns.str(text)
  if not text then return nil end
  text = text:gsub("^%s+", ""):gsub("[%s%.]+$", "")
  local negative = text:find("^%-") ~= nil   -- "%c" in a template matches the sign without capturing it
  local function out(keys, v)
    v = ns.ToNumber(v)
    if not v or v == 0 then return nil end
    if negative then v = -v end
    local t = {}
    if type(keys) == "table" then for _, k in ipairs(keys) do t[k] = v end else t[keys] = v end
    return t
  end
  for _, g in ipairs(SET_STAT_GLOBALS) do
    -- The text has lost its final period, so the template loses it too.
    local tmpl = ns.str(_G[g[1]])
    local pat = tmpl and ns.TemplatePattern((tmpl:gsub("[%s%.]+$", "")))
    local v = pat and text:match(pat)
    if v then return out(g[2], v) end
  end
  local lower = text:lower()
  for _, p in ipairs(ns.SET_STAT_PATTERNS) do
    local v = lower:match(p[1])
    if v then return out(p[2], v) end
  end
  return nil
end

-- True if tooltip lines are the item's real tooltip: some text, and not the
-- "Retrieving item information" placeholder shown before the data arrives.
function ns.TooltipLoaded(lines)
  if type(lines) ~= "table" or not lines[1] or not lines[1].left or lines[1].left == "" then return false end
  local retrieving = ns.str(RETRIEVING_ITEM_INFO) or "Retrieving item information"
  return lines[1].left ~= retrieving
end

-- A set piece's tooltip -> { name =, have =, total =, bonuses = { { idx =, active =, text = } } },
-- or nil when the item isn't part of a set.
function ns.ParseSetTooltip(lines)
  if type(lines) ~= "table" then return nil end
  local namePat = ns.TemplatePattern(ITEM_SET_NAME, true) or "^%s*(.-) %((%d+)/(%d+)%)%s*$"
  local grayPat = ns.TemplatePattern(ITEM_SET_BONUS_GRAY, true) or "^%s*%((%d+)%) Set: (.-)%s*$"
  local activePat = ns.TemplatePattern(ITEM_SET_BONUS, true) or "^%s*Set: (.-)%s*$"
  local set
  for i = 2, #lines do   -- line 1 is the item's own name
    local left = lines[i].left
    if left then
      if not set then
        local name, have, total = left:match(namePat)
        have, total = tonumber(have), tonumber(total)
        if name and have and total and total >= 2 and have <= total then
          set = { name = name, have = have, total = total, bonuses = {} }
        end
      else
        -- "(N) Set: text": active when N pieces are worn. Classic greys these and
        -- shows active ones as "Set: text"; modern clients keep the "(N)" on
        -- active bonuses too (green), and colour isn't in the text, so the
        -- piece count decides. The number is whichever capture is numeric.
        local c1, c2 = left:match(grayPat)
        local need, grayText
        if c1 then
          if tonumber(c1) then need, grayText = tonumber(c1), c2 else need, grayText = tonumber(c2), c1 end
        end
        if grayText and need then
          set.bonuses[#set.bonuses + 1] = { idx = #set.bonuses + 1, active = need <= set.have, text = grayText, need = need }
        else
          local text = left:match(activePat)
          if text then set.bonuses[#set.bonuses + 1] = { idx = #set.bonuses + 1, active = true, text = text } end
        end
      end
    end
  end
  return set
end

-- Reads each equipped set once (from the first piece found) and fills
-- data.setBonus (summed stats), data.setOther ({ set =, idx = } per active
-- bonus that isn't a plain stat) and data.setInfo (for /simx check).
function ns.CollectSetBonuses(data, missing)
  data.setBonus, data.setOther, data.setInfo = {}, {}, {}
  local seenID, byName, others = {}, {}, {}
  local noBonusLines = false   -- a set whose name line read but none of its bonus lines did
  local tipRead = {}   -- set ID -> a piece's tooltip was read (even if no set line was found)
  for _, g in ipairs(data.gear or {}) do
    -- Every item is checked, not just ones with a set ID: GetItemInfo can come
    -- back empty for an item the client hasn't cached, but its tooltip still works.
    if g.slot ~= ns.AMMO_SLOT and not ns.NO_STAT_SLOTS[g.slot] and not (g.set and seenID[g.set]) then
      local lines = ns.TooltipLines("inv", g.slot)
      if g.set and ns.TooltipLoaded(lines) then tipRead[g.set] = true end
      local set = ns.ParseSetTooltip(lines)
      local info = set and byName[set.name]
      if info then
        -- Seen already via a piece without a set ID: fill the ID in now.
        if g.set and info.id == 0 then info.id = g.set end
      elseif set then
        info = { id = g.set or 0, name = set.name, have = set.have, total = set.total, stats = {}, other = 0 }
        byName[set.name] = info
        if #set.bonuses == 0 and set.have >= 2 then noBonusLines = true end
        for _, b in ipairs(set.bonuses) do
          if b.active then
            local st = ns.ParseSetStat(b.text)
            if st then
              for k, v in pairs(st) do
                data.setBonus[k] = (data.setBonus[k] or 0) + v
                info.stats[k] = (info.stats[k] or 0) + v
              end
            else
              others[#others + 1] = { info = info, idx = b.idx }
              info.other = info.other + 1
            end
          end
        end
        data.setInfo[#data.setInfo + 1] = info
      end
      if info and info.id > 0 then seenID[info.id] = true end
    end
  end
  for i, o in ipairs(others) do data.setOther[i] = { set = o.info.id, idx = o.idx } end
  -- The tooltip's piece count is right even when some pieces' set IDs weren't loaded.
  for _, info in ipairs(data.setInfo) do
    if info.id > 0 and (data.sets[info.id] or 0) < info.have then data.sets[info.id] = info.have end
  end
  local seen = seenID
  -- A set worn with 2+ pieces whose tooltip never showed the set: its bonuses
  -- (if any are active) are missing. "setbonus" = tooltip unreadable (try
  -- again); "setparse" = read, but the set lines weren't recognised (new wording).
  local unreadable, unparsed = false, false
  for id, n in pairs(data.sets or {}) do
    if n >= 2 and not seen[id] then
      if tipRead[id] then unparsed = true else unreadable = true end
    end
  end
  if unreadable then missing[#missing + 1] = "setbonus" end
  if unparsed or noBonusLines then missing[#missing + 1] = "setparse" end
  -- Active bonuses from a set whose ID never loaded can't be matched by the sim.
  for _, o in ipairs(data.setOther) do
    if o.set == 0 then missing[#missing + 1] = "setid"; break end
  end
end

-- "Equip:" lines that are plain stats ("Equip: Improves your chance to hit by
-- 1%.") but missing from that item's GetItemStats: added to the item totals
-- and listed in data.equipFill, so nothing on the gear goes uncounted. A stat
-- the item already reports is never added twice.
function ns.CollectEquipEffects(data)
  data.equipFill = {}
  local prefix = ns.str(ITEM_SPELL_TRIGGER_ONEQUIP) or "Equip:"
  local unknown = data.unknownStatSlots or {}
  for _, g in ipairs(data.gear or {}) do
    local mine = data.perItem[g.slot]
    -- Skipped: unreadable items, ammo, shirt/tabard, and items with stat names
    -- this addon doesn't know (one of those might be the same stat).
    if mine and g.slot ~= ns.AMMO_SLOT and not ns.NO_STAT_SLOTS[g.slot] and not unknown[g.slot] then
      local found = {}   -- summed per item first: two "Equip:" lines can name one stat
      for _, l in ipairs(ns.TooltipLines("inv", g.slot) or {}) do
        local left = l.left
        if left and left:sub(1, #prefix) == prefix then
          local st = ns.ParseSetStat(left:sub(#prefix + 1))
          if not st then data.equipUnread = (data.equipUnread or 0) + 1 end
          for k, v in pairs(st or {}) do found[k] = (found[k] or 0) + v end
        end
      end
      local had = {}   -- the item's own stats, before any fill (so the twin check can't see its own additions)
      for k in pairs(mine) do had[k] = true end
      for k, v in pairs(found) do
        -- Ranged-only and general crit/hit may be one stat under two names.
        local twin = (k == "RCRIT" and "CRIT") or (k == "CRIT" and "RCRIT") or (k == "RHIT" and "HIT") or (k == "HIT" and "RHIT")
        if not had[k] and not (twin and had[twin]) then
          mine[k] = v
          data.itemStats[k] = (data.itemStats[k] or 0) + v
          data.equipFill[k] = (data.equipFill[k] or 0) + v
        end
      end
    end
  end
end

local function RankChar(r)
  r = ns.num(r) or 0
  if r < 0 then r = 0 end
  if r <= 9 then return tostring(math.floor(r)) end
  return string.char(string.byte("a") + math.min(r - 10, 25))   -- 10+ -> a..z (never seen in Classic trees)
end

-- Talent APIs. Current Classic clients use C_SpecializationInfo; the old
-- GetTalentInfo/GetTalentTabInfo only exist there as optional wrappers (the
-- loadDeprecationFallbacks setting), so they're the fallback. Forever is
-- reported (Sept 2026, not confirmed by Blizzard) to also lack GetNumTalentTabs
-- and GetNumTalents, so trees and talents are counted by asking until the
-- game stops answering, and a client that only gives points per tree still
-- exports those.
local MAX_TREES, MAX_TALENTS = 5, 40

local function SpecAPI()
  local SI = C_SpecializationInfo
  if type(SI) == "table" and not ns.IsSecret(SI) then return SI end
end

-- Tree name and points spent (points nil if the client doesn't say), or nil.
-- GetSpecializationInfo may return values (name 2nd, points 7th) or a table,
-- and may take an index or a query table.
local function TabInfo(t)
  local SI = SpecAPI()
  if SI and SI.GetSpecializationInfo then
    local r = { ns.try(SI.GetSpecializationInfo, t) }
    if next(r) == nil then r = { ns.try(SI.GetSpecializationInfo, { specializationIndex = t }) } end
    local first = r[1]
    local name, points
    if type(first) == "table" and not ns.IsSecret(first) then
      name, points = ns.StripCodes(first.name), ns.num(first.pointsSpent)
    else
      name, points = ns.StripCodes(r[2]), ns.num(r[7])
    end
    if name then
      if points == nil then   -- the old call may still know the tree's points
        local o = { ns.try(GetTalentTabInfo, t) }
        points = (ns.str(o[1]) and not tonumber(o[1])) and ns.num(o[3]) or (ns.num(o[1]) and ns.num(o[5])) or nil
      end
      return name, points
    end
  end
  -- Legacy: (name, icon, points, ...) on Classic; (id, name, description,
  -- icon, points, ...) on later clients.
  local r = { ns.try(GetTalentTabInfo, t) }
  if ns.str(r[1]) and not tonumber(r[1]) then return ns.StripCodes(r[1]), ns.num(r[3]) end
  if ns.num(r[1]) and ns.str(r[2]) then return ns.StripCodes(r[2]), ns.num(r[5]) end
  return nil, nil
end

-- tier, column, rank of talent i in tree t (each nil if unreadable).
-- The fourth return says which API answered ("C_SpecializationInfo" or "GetTalentInfo").
local function TalentInfo(t, i)
  local SI = SpecAPI()
  if SI and SI.GetTalentInfo then
    local info = ns.try(SI.GetTalentInfo, { specializationIndex = t, talentIndex = i })
    if type(info) == "table" and not ns.IsSecret(info) then
      local tier, column, rank = ns.num(info.tier), ns.num(info.column), ns.num(info.rank)
      -- A table with other field names says nothing: try the old call instead.
      if tier or column or rank then return tier, column, rank, "C_SpecializationInfo" end
    end
  end
  local _, _, tier, column, rank = ns.try(GetTalentInfo, t, i)
  tier, column, rank = ns.num(tier), ns.num(column), ns.num(rank)
  return tier, column, rank, (tier or column or rank) and "GetTalentInfo" or nil
end

-- Number of talent trees, or nil.
local function TreeCount()
  local n = ns.num(ns.try(GetNumTalentTabs))
  if n and n > 0 then return n end
  local count = 0
  for t = 1, MAX_TREES do
    if TabInfo(t) then count = t else break end
  end
  return count > 0 and count or nil
end

-- Which talent API this client has, for /simx check: a short description or nil.
function ns.TalentAPIAvailable()
  if not TreeCount() then return nil end
  -- Named only if it really answers for the first talent, as the export needs.
  local _, _, _, which = TalentInfo(1, 1)
  if which then return which end
  local _, spent = TabInfo(1)
  return spent and "points per tree only" or nil
end

-- Talent trees. Ranks are listed by tier, then column, which is how talent
-- calculators lay a tree out.
function ns.CollectTalents(data, missing)
  local nTabs = TreeCount()
  if not nTabs then
    missing[#missing + 1] = "talents"
    return
  end
  local tabs, unreadable, answered, spentKnown = {}, false, false, true
  for t = 1, nTabs do
    local name, spent = TabInfo(t)
    if spent == nil then spentKnown = false end
    local n = ns.num(ns.try(GetNumTalents, t))
    if n and n <= 0 then n = nil end   -- 0 says nothing: count by asking instead
    local list, treeBad = {}, false
    for i = 1, n or MAX_TALENTS do
      local tier, column, rank = TalentInfo(t, i)
      local any = tier or column or rank
      -- A real talent sits at tier 1+ and column 1+ (zeroed answers aren't talents).
      local placed = tier and column and tier >= 1 and column >= 1
      if any then answered = true end
      if not n and not placed then break end   -- counting by asking: the first non-talent is the end
      if placed then
        if not rank then treeBad = true end
        list[#list + 1] = { tier = tier, column = column, i = i, rank = rank or 0 }
      else
        treeBad = true
      end
    end
    table.sort(list, function(a, b)
      if a.tier ~= b.tier then return a.tier < b.tier end
      if a.column ~= b.column then return a.column < b.column end
      return a.i < b.i
    end)
    local chars, points = {}, 0
    for _, x in ipairs(list) do
      chars[#chars + 1] = RankChar(x.rank)
      points = points + math.max(0, x.rank)
    end
    -- The tree's own points total disagreeing with the ranks means a rank was misread.
    if answered and spent and spent ~= points then treeBad = true end
    -- A tree whose ranks didn't all read: its own total is the better number.
    if treeBad then
      unreadable = true
      if spent then points = spent end
    end
    tabs[t] = { name = name, points = points, ranks = table.concat(chars), spent = spent }
  end
  if not answered then
    if spentKnown then
      -- Only points per tree: export those, without per-talent ranks.
      for _, tab in ipairs(tabs) do tab.points, tab.ranks = tab.spent, "" end
      data.talents = tabs
      missing[#missing + 1] = "talentranks"
    else
      -- Trees exist but nothing about talents answered: an API problem.
      missing[#missing + 1] = "talentapi"
    end
    return
  end
  data.talents = tabs
  if unreadable then missing[#missing + 1] = "talents" end
end

local SCHOOLS = { 2, 3, 4, 5, 6, 7 }   -- holy, fire, nature, frost, shadow, arcane

-- The character sheet: total (buffed) values, plus unbuffed stats.
function ns.CollectSheet(data, missing)
  local sh, bs = {}, {}
  for i, key in ipairs(ns.BASE_KEYS) do
    if i <= 5 then
      -- UnitStat returns stat, effectiveStat, posBuff, negBuff. The effective
      -- value is what the sheet shows; minus buffs gives gear + base only.
      local _, eff, pos, neg = ns.try(UnitStat, "player", i)
      eff, pos, neg = ns.num(eff), ns.num(pos), ns.num(neg)
      sh[key] = eff
      if eff then bs[key] = eff - (pos or 0) - (neg or 0) end
    end
  end
  local function power(fn)
    local base, pos, neg = ns.try(fn, "player")
    base, pos, neg = ns.num(base), ns.num(pos), ns.num(neg)
    if not base then return nil, nil end
    return base + (pos or 0) + (neg or 0), base
  end
  sh.ap, bs.ap = power(UnitAttackPower)
  sh.rap, bs.rap = power(UnitRangedAttackPower)
  sh.crit = ns.num(ns.try(GetCritChance))
  sh.rcrit = ns.num(ns.try(GetRangedCritChance))
  local scrit, sp
  for _, school in ipairs(SCHOOLS) do
    local c = ns.num(ns.try(GetSpellCritChance, school))
    if c and (not scrit or c > scrit) then scrit = c end
    local d = ns.num(ns.try(GetSpellBonusDamage, school))
    if d and (not sp or d > sp) then sp = d end
  end
  sh.scrit, sh.sp = scrit, sp
  sh.heal = ns.num(ns.try(GetSpellBonusHealing))
  sh.hit = ns.num(ns.try(GetHitModifier))
  sh.shit = ns.num(ns.try(GetSpellHitModifier))
  local a1, a2 = ns.try(UnitArmor, "player")
  sh.armor = ns.num(a2) or ns.num(a1)
  for _, key in ipairs({ "str", "agi", "ap", "crit", "hit" }) do
    if sh[key] == nil then missing[#missing + 1] = "sheet." .. key end
  end
  data.sheet, data.base = sh, bs
end

function ns.CollectAuras(data)
  local ids = {}
  for i = 1, 40 do
    local id
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local aura = ns.try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if type(aura) ~= "table" then break end
      id = ns.num(aura.spellId)
    elseif type(UnitBuff) == "function" then
      local name = ns.try(UnitBuff, "player", i)
      if ns.IsSecret(name) or not name then break end
      id = ns.num(select(10, ns.try(UnitBuff, "player", i)))
    else
      break
    end
    if id then ids[#ids + 1] = id end
  end
  data.auras = ids
end

-- Everything. Returns data, or nil + reason (in combat).
function ns.Collect()
  if ns.InCombat() then return nil, "in combat" end
  ns.tipCache = {}
  local ok, data, missing = pcall(ns.CollectAll)
  ns.tipCache = nil
  if not ok then error(data, 0) end
  data.missing = missing
  return data
end

function ns.CollectAll()
  local data, missing = {}, {}
  local version, build = ns.try(GetBuildInfo)
  version, build = ns.str(version), ns.str(build) or (ns.num(build) and tostring(build))
  data.build = version and (build and (version .. "." .. build) or version) or nil
  data.date = date and ns.str(date("%Y-%m-%d")) or nil
  data.class = ns.str(select(2, ns.try(UnitClass, "player")))
  data.race = ns.str(select(2, ns.try(UnitRace, "player")))
  -- Faction tells Skyborne apart: High Order (Alliance) vs Windshaper (Horde).
  data.faction = ns.str(ns.try(UnitFactionGroup, "player"))
  data.level = ns.num(ns.try(UnitLevel, "player"))
  if not data.class then missing[#missing + 1] = "class" end
  if not data.level then missing[#missing + 1] = "level" end
  ns.CollectTalents(data, missing)
  ns.CollectGear(data, missing)
  ns.CollectSetBonuses(data, missing)
  ns.CollectEquipEffects(data)
  -- Stat wording is only fully known in English. On other clients, "Equip:"
  -- or set lines that didn't read as stats may be stats in another language.
  local locale = ns.str(ns.try(GetLocale)) or "enUS"
  data.locale = locale
  if locale ~= "enUS" and locale ~= "enGB" and ((data.equipUnread or 0) > 0 or #data.setOther > 0) then
    missing[#missing + 1] = "locale"
  end
  ns.CollectQuiver(data, missing)
  ns.CollectSheet(data, missing)
  ns.CollectAuras(data)
  return data, missing
end

-- Plain-language notes about an export, shown under the string.
function ns.Warnings(data)
  local w = {}
  local miss = {}
  for _, k in ipairs(data.missing or {}) do miss[k] = true end
  if miss.class then w[#w + 1] = "Couldn't read your class; export again in a moment." end
  if data.level and data.level < 60 then
    w[#w + 1] = "You're level " .. data.level .. "; the sim models level 60."
  end
  if miss.talentranks then
    local pts = {}
    for i, t in ipairs(data.talents or {}) do pts[i] = tostring(t.points or 0) end
    w[#w + 1] = "Your game only reports points per talent tree, so the string has your totals ("
      .. table.concat(pts, "/") .. ") but not each talent. Pick your talents in the sim."
  elseif miss.talentapi then
    w[#w + 1] = "The game's talent functions didn't answer, so talents aren't in the string."
      .. " Type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page."
  elseif miss.talents and not data.talents then
    w[#w + 1] = "Couldn't find your talents (this client has no talent functions SimBench knows). Pick them in the sim."
  elseif miss.talents then
    w[#w + 1] = "Couldn't read all your talents; check them in the sim, or open your talent window once and export again."
  elseif data.talents and data.level and data.level >= 10 then
    local total = 0
    for _, t in ipairs(data.talents) do total = total + (t.points or 0) end
    if total == 0 then w[#w + 1] = "No talent points found. If you've spent some, open your talent window once and export again." end
  end
  if miss.itemstats and miss.notloaded then
    w[#w + 1] = "Your items hadn't loaded yet, so item stats are missing. Export again in a few seconds."
  elseif miss.itemstats then
    w[#w + 1] = "Couldn't read item stats; the sim will fall back to character-sheet values."
  end
  local notLoadedSlot = {}
  for _, g in ipairs(data.gear or {}) do if g.notLoaded then notLoadedSlot[g.slot] = true end end
  local waiting, unreadable = {}, {}
  for _, k in ipairs(data.missing or {}) do
    local slot = tonumber(k:match("^itemstats(%d+)$"))
    if slot then
      local list = notLoadedSlot[slot] and waiting or unreadable
      list[#list + 1] = slot
    end
  end
  if #waiting > 0 then
    w[#w + 1] = "Some items hadn't loaded yet (" .. SlotList(waiting)
      .. "), so their stats are missing. Export again in a few seconds."
  end
  if #unreadable > 0 then
    w[#w + 1] = "Couldn't read the stats of some items (" .. SlotList(unreadable) .. "), so totals are low."
      .. " Export again; if it keeps happening, type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page."
  end
  local notLoaded = {}
  for _, g in ipairs(data.gear or {}) do if g.notLoaded then notLoaded[g.slot] = true end end
  local badWeapons, waitWeapons = {}, {}
  for _, slot in ipairs(ns.WEAPON_SLOTS) do
    if miss["weapon" .. slot] then
      local list = notLoaded[slot] and waitWeapons or badWeapons
      list[#list + 1] = slot
    end
  end
  if #waitWeapons > 0 then
    w[#w + 1] = "Couldn't read weapon damage (" .. SlotList(waitWeapons) .. ") because it hadn't loaded yet."
      .. " Export again in a few seconds."
  end
  if #badWeapons > 0 then
    w[#w + 1] = "Couldn't read weapon damage (" .. SlotList(badWeapons) .. "). Export again; if it keeps happening,"
      .. " type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page."
  end
  if miss.setbonus then
    w[#w + 1] = "Couldn't read your set bonuses, so their stats aren't counted. Export again in a moment."
  end
  if miss.setparse then
    w[#w + 1] = "Your set pieces' tooltips didn't show their set the way SimBench expects, so set bonuses aren't counted."
      .. " Type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page."
  end
  if miss.setid then
    w[#w + 1] = "Couldn't tell which set a bonus belongs to (item data not loaded). Export again in a few seconds."
  end
  local other = data.setOther and #data.setOther or 0
  if other > 0 then
    w[#w + 1] = other .. " active set bonus" .. (other > 1 and "es" or "") .. " couldn't be turned into stats"
      .. " (procs, ability changes and conditional bonuses can't), so " .. (other > 1 and "they're" or "it's")
      .. " listed for the sim but not added to your stats."
  end
  if miss.locale then
    w[#w + 1] = "Your game isn't in English, and SimBench only reads some \"Equip:\" and set-bonus stats in"
      .. " other languages. Check your hit and crit in the sim."
  end
  if data.class == "HUNTER" then
    if miss.ammo then
      w[#w + 1] = "Couldn't read your ammo's damage per second. Export again in a few seconds."
    elseif not data.ammoDps then
      w[#w + 1] = "No ammo found; the sim will assume none."
    end
    if miss.quiver then
      w[#w + 1] = "Found your quiver but couldn't read its haste; the sim will assume none. Export again in a few seconds."
    elseif not data.quiverHaste then
      w[#w + 1] = "No quiver or ammo pouch found; the sim will assume no quiver haste."
    end
  end
  return w
end
