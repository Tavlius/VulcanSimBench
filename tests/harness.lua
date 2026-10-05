-- Mock WoW client for SimBench tests. boot(opts) builds a fresh client and loads
-- the addon in TOC order. opts.client lets a test change what the APIs return.
local H = {}
local DIR = os.getenv("SX_DIR") or "../"

local SECRET = newproxy(true)
do
  local mt = getmetatable(SECRET)
  local function boom() error("secret value touched", 2) end
  for _, k in ipairs({ "__index", "__newindex", "__lt", "__le", "__add", "__sub", "__mul", "__div",
      "__mod", "__unm", "__concat", "__len", "__call" }) do mt[k] = boom end
  mt.__tostring = function() return "<secret>" end
end
H.SECRET = SECRET
local rawtype = type

local function tocFiles()
  local files = {}
  for line in io.lines(DIR .. "VulcanSimBench.toc") do
    if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
  end
  return files
end

-- A tiny frame object: records scripts, text and visibility.
local function newFrame(kind, name)
  local f = { kind = kind, name = name, scripts = {}, shown = false, events = {}, text = "", points = {} }
  local mt = {}
  mt.__index = function(t, k)
    local m = {
      SetScript = function(self, ev, fn) self.scripts[ev] = fn end,
      GetScript = function(self, ev) return self.scripts[ev] end,
      RegisterEvent = function(self, ev) self.events[ev] = true end,
      UnregisterEvent = function(self, ev) self.events[ev] = nil end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.shown = false end,
      IsShown = function(self) return self.shown end,
      SetText = function(self, s) self.text = s end,
      GetText = function(self) return self.text end,
      HighlightText = function(self) self.highlighted = true end,
      SetFocus = function(self) self.focused = true end,
      CreateFontString = function(self) local fs = newFrame("FontString"); self.fontStrings = self.fontStrings or {}
        self.fontStrings[#self.fontStrings + 1] = fs; return fs end,
      -- About 90 characters per 12-pixel line at the copy box's width.
      GetStringHeight = function(self) local n = 0
        for line in (self.text .. "\n"):gmatch("([^\n]*)\n") do n = n + math.max(1, math.ceil(#line / 90)) end
        return n * 12 end,
      SetHeight = function(self, v) self.height = v end,
      GetHeight = function(self) return self.height end,
    }
    if m[k] then return m[k] end
    -- Any other widget method (PascalCase) is a no-op; other keys are plain
    -- fields, nil until set, as on a real frame.
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end
  return setmetatable(f, mt)
end
H.newFrame = newFrame

-- Default character: a level-60 Human Hunter with a bow, ammo and a quiver.
function H.defaultClient()
  return {
    combat = false, lockdown = false, class = "HUNTER", race = "Human", level = 60,
    build = { "1.60.1", "70009" },
    items = {
      [1] = { link = "|cff0070dd|Hitem:16846:0:0:0|h[Giantstalker's Helmet]|h|r",
        stats = { ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 15, RESISTANCE0_NAME = 300 } },
      [16] = { link = "|Hitem:12784:1900:0:0|h[Arcanite Reaper]|h", loc = "INVTYPE_2HWEAPON",
        stats = { ITEM_MOD_STRENGTH_SHORT = 13, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 62.1, ITEM_MOD_ATTACK_POWER_SHORT = 62 },
        tip = { { left = "Arcanite Reaper" }, { left = "Two-Hand", right = "Axe" },
                { left = "153 - 256 Damage", right = "Speed 3.80" }, { left = "(53.8 damage per second)" } } },
      [18] = { link = "|Hitem:18713:0|h[Rhok'delar]|h", loc = "INVTYPE_RANGED",
        stats = { ITEM_MOD_AGILITY_SHORT = 11, ITEM_MOD_CRIT_RATING_SHORT = 1 },
        tip = { { left = "Rhok'delar" }, { left = "Ranged", right = "Bow" },
                { left = "+5 - 10 Fire Damage" },
                { left = "82 - 124 Damage", right = "Speed 3.30" } } },
    },
    ammo = { id = 11630, tip = { { left = "Rockshard Pellets" }, { left = "Adds 17.5 damage per second" } } },
    bags = { [1] = { id = 18714, classID = 11, tip = { { left = "Ancient Sinew Wrapped Lamina" },
      { left = "Quiver" }, { left = "Increases ranged attack speed by 15%." } } } },
    -- Talents are deliberately NOT in tier/column order (the client's index
    -- order isn't), so the sort is exercised: sorted BM ranks are 5 0 3 2.
    talents = {
      { name = "Beast Mastery", list = { { 2, 2, 2 }, { 1, 3, 0 }, { 2, 1, 3 }, { 1, 2, 5 } } },
      { name = "Marksmanship", list = { { 1, 2, 5 }, { 2, 3, 3 } } },
      { name = "Survival", list = { { 1, 1, 0 } } },
    },
    stat = { { 55, 70, 0, 0 }, { 125, 260, 20, 0 }, { 90, 200, 0, 0 }, { 65, 100, 0, 0 }, { 70, 80, 0, 0 } },
    ap = { 600, 100, 0 }, rap = { 900, 150, 0 },
    crit = 12.3, rcrit = 14.1, hit = 3, shit = 0, spellCrit = 5.1, spellDmg = 0, heal = 0, armor = { 2000, 2100 },
    auras = { 1126, 27681 },
  }
end

function H.boot(opts)
  opts = opts or {}
  local c = opts.client or H.defaultClient()
  c.printed = {}
  c.instant = function(id)
    for _, b in pairs(c.bags or {}) do if b.id == id then return id, nil, nil, "INVTYPE_BAG", nil, b.classID, 0 end end
    for _, it in pairs(c.items) do
      if tonumber(it.link:match("item:(%d+)")) == id then return id, nil, nil, it.loc or "INVTYPE_HEAD", nil, 4, 0 end
    end
    return id, nil, nil, nil, nil, 2, 0
  end
  local function sec(v, key) if c.secret and c.secret[key] then return SECRET end return v end

  _G.issecretvalue = opts.noSecretApi and nil or function(v) return rawequal(v, SECRET) end
  _G.type = function(v) if rawequal(v, SECRET) then return c.secretType or "number" end return rawtype(v) end
  _G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    c.printed[#c.printed + 1] = table.concat(t, " ")
  end
  _G.date = function(fmt) return os.date("!" .. fmt, 1790000000) end
  _G.unpack = unpack
  _G.VulcanSimBenchCharDB = opts.saved
  -- Saved-data safety (Persist.lua): the account marker, who's playing, and where warnings go.
  _G.VulcanSimBenchDB = opts.marker
  _G.time = function() return 1790000000 end   -- (WoW's time(); fixed, like date() above)
  _G.UnitName = function(unit) if unit == "player" then return opts.name or "Tavlius" end end
  _G.GetNormalizedRealmName = function() if opts.realm == false then return nil end return opts.realm or "Emberfall" end
  c.uiErrors = {}
  _G.UIErrorsFrame = { AddMessage = function(_, msg) c.uiErrors[#c.uiErrors + 1] = msg end }
  _G.DAMAGE_TEMPLATE = opts.damageTemplate or "%s - %s Damage"
  _G.AMMO_DAMAGE_TEMPLATE = opts.ammoTemplate or "Adds %s damage per second"
  _G.SINGLE_DAMAGE_TEMPLATE = "%s Damage"
  _G.ARMOR_TEMPLATE = "%s Armor"
  _G.RETRIEVING_ITEM_INFO = "Retrieving item information"
  _G.GetLocale = function() return opts.locale or "enUS" end
  if opts.noTemplates then _G.DAMAGE_TEMPLATE, _G.AMMO_DAMAGE_TEMPLATE = nil, nil end
  _G.ITEM_SET_NAME, _G.ITEM_SET_BONUS, _G.ITEM_SET_BONUS_GRAY = "%s (%d/%d)", "Set: %s", "(%d) Set: %s"
  if opts.noSetTemplates then _G.ITEM_SET_NAME, _G.ITEM_SET_BONUS, _G.ITEM_SET_BONUS_GRAY = nil, nil, nil end
  -- Client stat strings (enUS); opts.statGlobals replaces them (e.g. German).
  local SG = opts.statGlobals or { ITEM_MOD_AGILITY = "%c%d Agility", ITEM_MOD_STRENGTH = "%c%d Strength",
    ITEM_MOD_STAMINA = "%c%d Stamina", ITEM_MOD_INTELLECT = "%c%d Intellect", ITEM_MOD_SPIRIT = "%c%d Spirit",
    ITEM_MOD_ATTACK_POWER = "Increases attack power by %s.", ITEM_MOD_RANGED_ATTACK_POWER = "Increases ranged attack power by %s.",
    ITEM_MOD_MANA_REGENERATION = "Restores %s mana per 5 sec.", ITEM_RESIST_ALL = "%c%d to All Resistances" }
  for _, k in ipairs({ "ITEM_MOD_AGILITY", "ITEM_MOD_STRENGTH", "ITEM_MOD_STAMINA", "ITEM_MOD_INTELLECT", "ITEM_MOD_SPIRIT",
      "ITEM_MOD_ATTACK_POWER", "ITEM_MOD_RANGED_ATTACK_POWER", "ITEM_MOD_MANA_REGENERATION", "ITEM_RESIST_ALL" }) do
    _G[k] = SG[k]
  end

  _G.InCombatLockdown = function() return sec(c.lockdown, "lockdown") end
  _G.UnitAffectingCombat = function() return sec(c.combat, "combat") end
  _G.GetBuildInfo = function() return c.build[1], c.build[2] end
  _G.UnitClass = function() return "Hunter", sec(c.class, "class") end
  _G.UnitRace = function() return "Human", c.race end
  _G.UnitLevel = function() return sec(c.level, "level") end
  _G.UnitFactionGroup = function() return c.faction or "Alliance", c.faction or "Alliance" end
  _G.GetItemInfo = nil
  _G.GetInventoryItemLink = function(_, slot)
    local it = c.items[slot]
    return it and sec(it.link, "link") or nil
  end
  _G.GetInventoryItemID = function(_, slot)
    if slot == 0 then return c.ammo and c.ammo.id or nil end
    for bag, b in pairs(c.bags or {}) do if slot == 19 + bag then return b.id end end
    local it = c.items[slot]
    return it and tonumber(it.link:match("item:(%d+)")) or nil
  end
  local function statsFor(link)
    for _, it in pairs(c.items) do if it.link == link then return it.stats end end
  end
  if not opts.noItemStats then
    _G.C_Item = {
      GetItemStats = function(link) return statsFor(link) end,
      GetItemInfoInstant = function(id) return c.instant(id) end,
      RequestLoadItemDataByID = function(id) c.requested = c.requested or {}; c.requested[#c.requested + 1] = id end,
      GetItemInfo = function(link)
        for _, it in pairs(c.items) do
          if it.link == link and not it.uncached then
            return "n", link, 4, 60, 60, "Armor", "Mail", 1, it.loc or "INVTYPE_HEAD", 0, 100, 4, 0, 1, 0, it.setID, false
          end
        end
      end,
    }
  else
    _G.C_Item = { GetItemInfoInstant = function(id) return c.instant(id) end }
  end
  _G.GetItemStats = nil
  _G.C_Container = { ContainerIDToInventoryID = function(bag) return 19 + bag end }
  local function lines(tip) return tip and { lines = (function()
    local out = {}
    for i, l in ipairs(tip) do out[i] = { leftText = sec(l.left, "tip"), rightText = l.right } end
    return out end)() } or nil end
  -- Tooltip reading: "scan" (default; the live Classic client has no
  -- C_TooltipInfo, so the hidden GameTooltip is what really runs) or "api"
  -- (C_TooltipInfo, for clients that have it). run.sh runs the suite both ways.
  local tipMode = opts.tipMode or os.getenv("SX_TIPMODE") or "scan"
  if tipMode == "api" and not opts.noTooltipInfo then
    _G.C_TooltipInfo = {
      GetInventoryItem = function(_, slot)
        if c.items[slot] then return lines(c.items[slot].tip) end
        for bag, b in pairs(c.bags or {}) do if slot == 19 + bag then return lines(b.tip) end end
      end,
      GetItemByID = function(id) if c.ammo and c.ammo.id == id then return lines(c.ammo.tip) end end,
    }
  else
    _G.C_TooltipInfo = nil
  end
  _G.C_SpecializationInfo = nil
  _G.ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
  _G.GetNumTalentTabs, _G.GetTalentTabInfo, _G.GetNumTalents, _G.GetTalentInfo = nil, nil, nil, nil
  if not opts.noTalents then
    -- opts.forever: no GetNumTalentTabs/GetNumTalents (reported missing on Forever);
    -- opts.noTalentInfo: no per-talent call at all (points per tree only);
    -- opts.specTable: GetSpecializationInfo returns a table; opts.specQuery: it
    -- only accepts a query table.
    if not opts.forever then
      _G.GetNumTalentTabs = function() return #c.talents end
      _G.GetNumTalents = function(t) return #c.talents[t].list end
    end
    if not opts.legacyTalents then
      -- Current Classic clients: C_SpecializationInfo. The old functions below
      -- only exist with opts.alsoLegacy (the loadDeprecationFallbacks setting).
      _G.C_SpecializationInfo = {   -- (GetTalentInfo removed below for opts.noTalentInfo)
        GetSpecializationInfo = function(t)
          if opts.specQuery then
            if type(t) ~= "table" then return end
            t = t.specializationIndex
          elseif type(t) ~= "number" then
            error("bad argument")
          end
          local tab = c.talents[t]
          if not tab then return nil end
          local pts = 0
          for _, x in ipairs(tab.list) do pts = pts + x[3] end
          if opts.specTable then return { specID = 100 + t, name = sec(tab.name, "tabname"), pointsSpent = tab.spentOverride or pts } end
          return 100 + t, sec(tab.name, "tabname"), "desc", "icon", "DAMAGER", 2, tab.spentOverride or pts, "bg", 0, true
        end,
        GetTalentInfo = function(q)
          local tab = c.talents[q.specializationIndex]
          local x = tab and tab.list[q.talentIndex]
          if not x then return nil end
          return { name = "T" .. q.talentIndex, icon = "icon", tier = x[1], column = x[2], rank = sec(x[3], "rank"), maxRank = 5 }
        end,
      }
    end
    if opts.noTalentInfo and _G.C_SpecializationInfo then _G.C_SpecializationInfo.GetTalentInfo = nil end
    if opts.legacyTalents or opts.alsoLegacy then
      -- Classic shape (name, icon, points) or the later one (id, name, description, icon, points).
      _G.GetTalentTabInfo = function(t)
        local tab = c.talents[t]
        if not tab then return nil end
        local pts = 0
        for _, x in ipairs(tab.list) do pts = pts + x[3] end
        pts = tab.spentOverride or pts
        if opts.wrathTabInfo then return 100 + t, tab.name, "desc", "icon", pts end
        return tab.name, "icon", pts
      end
      if not opts.noTalentInfo then
        _G.GetTalentInfo = function(t, i)
          local x = c.talents[t] and c.talents[t].list[i]
          if not x then return nil end
          return "T" .. i, "icon", x[1], x[2], sec(x[3], "rank"), 5
        end
      end
    end
  end
  _G.UnitStat = function(_, i) local s = c.stat[i]; return s[1], sec(s[2], "stat"), s[3], s[4] end
  _G.UnitAttackPower = function() return sec(c.ap[1], "ap"), c.ap[2], c.ap[3] end
  _G.UnitRangedAttackPower = function() return c.rap[1], c.rap[2], c.rap[3] end
  _G.GetCritChance = function() return sec(c.crit, "crit") end
  _G.GetRangedCritChance = function() return c.rcrit end
  -- Per-school values when given as a table ({ [2] = holy, ... }), else one value for all.
  _G.GetSpellCritChance = function(school) if type(c.spellCrit) == "table" then return c.spellCrit[school] end return c.spellCrit end
  _G.GetSpellBonusDamage = function(school) if type(c.spellDmg) == "table" then return c.spellDmg[school] end return c.spellDmg end
  _G.GetSpellBonusHealing = function() return c.heal end
  _G.GetHitModifier = function() return c.hit end
  _G.GetSpellHitModifier = function() return c.shit end
  _G.UnitArmor = function() return c.armor[1], c.armor[2] end
  _G.C_UnitAuras = {
    GetAuraDataByIndex = function(_, i) local id = c.auras[i]; return id and { spellId = sec(id, "aura") } or nil end,
  }
  _G.UnitBuff = nil

  c.frames = {}
  _G.CreateFrame = function(kind, name)
    if c.noFrames then error("no frames") end
    local f = newFrame(kind, name)
    c.frames[#c.frames + 1] = f
    if kind == "GameTooltip" and not opts.noScanTip then
      -- A scanning tooltip: Set* fills numbered left/right font strings.
      local n = 0
      local function fill(tip)
        n = 0
        for i, l in ipairs(tip or {}) do
          n = i
          local L, R = newFrame("FontString"), newFrame("FontString")
          L.text, R.text = sec(l.left, "tip"), l.right
          L.shown, R.shown = l.left ~= nil, l.right ~= nil   -- unused right lines are hidden
          _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = L, R
        end
      end
      rawset(f, "SetInventoryItem", function(_, _, slot)
        if c.items[slot] then fill(c.items[slot].tip) return end
        for bag, b in pairs(c.bags or {}) do if slot == 19 + bag then fill(b.tip) return end end
        fill(nil)
      end)
      rawset(f, "SetItemByID", function(_, id) fill(c.ammo and c.ammo.id == id and c.ammo.tip or nil) end)
      rawset(f, "NumLines", function() return n end)
      rawset(f, "ClearLines", function() n = 0 end)
    end
    if name then _G[name] = f end
    return f
  end
  _G.UIParent = newFrame("Frame", "UIParent")
  _G.WorldFrame = _G.UIParent
  _G.PaperDollFrame = nil
  if not opts.noPaperDoll then _G.PaperDollFrame = newFrame("Frame", "PaperDollFrame") end
  _G.CharacterFrame = nil
  _G.UISpecialFrames = {}
  _G.GameTooltip = newFrame("GameTooltip", "GameTooltip")
  _G.ChatFontNormal = {}
  _G.BackdropTemplateMixin = {}
  _G.SlashCmdList = {}

  local ns = {}
  for _, file in ipairs(tocFiles()) do
    local chunk = assert(loadfile(DIR .. file))
    chunk("VulcanSimBench", ns)
  end
  -- Fire ADDON_LOADED on every frame listening for it.
  for _, f in ipairs(c.frames) do
    if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "VulcanSimBench") end
  end
  local h = { c = c, ns = ns }
  -- Logging out fires PLAYER_LOGOUT before the client writes both saved files.
  function h.logout()
    for _, f in ipairs(c.frames) do
      if f.events.PLAYER_LOGOUT and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_LOGOUT") end
    end
    return { char = _G.VulcanSimBenchCharDB, marker = _G.VulcanSimBenchDB }
  end
  function h.printedMatch(pat)
    for _, p in ipairs(c.printed) do if p:find(pat) then return p end end
  end
  return h
end

-- Runs a slash command the way chat does: input cut at 255 characters.
function H.slash(msg)
  return _G.SlashCmdList.VULCANSIMBENCH(msg:sub(1, 255))
end

-- Decoded field "k1:v1,k2:v2" -> map, for exact comparisons.
function H.kv(field)
  local t = {}
  for k, v in (field or ""):gmatch("([^,:]+):([^,]+)") do t[k] = v end
  return t
end

-- Tiny test runner.
local results = { pass = 0, fail = 0 }
function H.check(name, cond, detail)
  if cond then results.pass = results.pass + 1
  else
    results.fail = results.fail + 1
    io.write("FAIL: " .. name .. (detail ~= nil and ("  -> " .. tostring(detail)) or "") .. "\n")
  end
end
function H.finish(label)
  io.write(string.format("%s: %d passed, %d failed\n", label, results.pass, results.fail))
  os.exit(results.fail == 0 and 0 or 1)
end
return H
