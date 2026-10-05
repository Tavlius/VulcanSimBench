-- SimBench: slash commands, the export flow, and diagnostics.
local _, ns = ...

-- Builds the string and opens the copy box. Returns the string (or nil).
function ns.Export()
  -- An unexpected error gets a plain message and is kept for /simx debug.
  local ok, data = pcall(ns.Collect)
  if not ok then
    ns.lastError = tostring(data)
    ns.Print("Export failed: " .. ns.lastError .. ". Type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page.")
    return nil
  end
  if not data then
    ns.Print("Can't export during combat: the game hides stats from addons until the fight ends. Try again after.")
    return nil
  end
  local s = ns.Encode(data)
  VulcanSimBenchCharDB = VulcanSimBenchCharDB or {}
  local notes = ns.Warnings(data)
  VulcanSimBenchCharDB.last, VulcanSimBenchCharDB.lastNotes = s, notes
  -- Notes go in the copy window; chat gets one line so it isn't spammed.
  if #notes > 0 then
    ns.Print("Export ready with " .. #notes .. " note(s) (shown under the string). Ctrl+C (Cmd+C on a Mac) to copy.")
  else
    ns.Print("Export ready. Ctrl+C (Cmd+C on a Mac) to copy, then paste into the sim.")
  end
  ns.ShowCopy(s, notes)
  return s
end

local function yes(v) return v and "|cff33ff33yes|r" or "|cffff5555no|r" end

-- What this client supports, and what an export would read right now.
function ns.CheckLines()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  add("SimBench " .. ns.VERSION .. " (format " .. ns.FORMAT .. ")")
  if ns.Persist then add(ns.Persist.CheckLine()) end
  add("Secret values: " .. yes(issecretvalue) .. ", in combat now: " .. yes(ns.InCombat()))
  add("Tooltip data API: " .. yes(C_TooltipInfo and C_TooltipInfo.GetInventoryItem)
    .. (C_TooltipInfo and "" or " (fine: the hidden tooltip is used)")
    .. ", item stats API: " .. yes((C_Item and C_Item.GetItemStats) or GetItemStats))
  local talentAPI = ns.TalentAPIAvailable()
  add("Talent API: " .. yes(talentAPI) .. (talentAPI and (" (" .. talentAPI .. ")") or "")
    .. ", aura API: " .. yes((C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) or UnitBuff))
  add("Damage template: " .. tostring(ns.str(DAMAGE_TEMPLATE) or "(none, using English)"))
  if ns.InCombat() then
    add("Leave combat for the rest of the check.")
    return lines
  end
  local ok, data = pcall(ns.Collect)
  if not ok then
    ns.lastError = tostring(data)
    add("The check hit an error: " .. ns.lastError
      .. ". Type /simx debug, Ctrl+C, and attach it to a bug report on the add-on's issues page.")
    return lines
  end
  if not data then
    add("Combat started during the check; try again after the fight.")
    return lines
  end
  add("Class " .. tostring(data.class) .. ", race " .. tostring(data.race) .. ", level " .. tostring(data.level)
    .. ", build " .. tostring(data.build))
  if data.talents then
    local p = {}
    for i, t in ipairs(data.talents) do p[i] = (t.name or "?") .. " " .. t.points end
    add("Talents: " .. table.concat(p, " / "))
  end
  add("Items equipped: " .. #data.gear)
  for _, slot in ipairs(ns.WEAPON_SLOTS) do
    local w = data.weapons[slot]
    if w then
      add(("Weapon slot %d: %s - %s, speed %s (%s)"):format(slot, ns.fmt(w.min), ns.fmt(w.max), ns.fmt(w.speed),
        w.loc or "type unknown"))
    end
  end
  if data.ammoDps then add("Ammo: " .. ns.fmt(data.ammoDps, 1) .. " damage per second") end
  if data.quiverHaste then add("Quiver: " .. ns.fmt(data.quiverHaste, 1) .. "% ranged haste") end
  for _, s in ipairs(data.setInfo or {}) do
    local st = {}
    for _, k in ipairs(ns.SortedKeys(s.stats)) do st[#st + 1] = (s.stats[k] >= 0 and "+" or "") .. ns.fmt(s.stats[k]) .. " " .. k end
    add(("Set %s (%d/%d, id %s): %s%s"):format(s.name, s.have, s.total, s.id == 0 and "unknown" or s.id,
      #st > 0 and table.concat(st, ", ") or "no stat bonuses active",
      s.other > 0 and (", " .. s.other .. " other bonus(es)") or ""))
  end
  local keys = ns.SortedKeys(data.itemStats)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. " " .. ns.fmt(data.itemStats[k]) end
  add("Item stat totals: " .. (#parts > 0 and table.concat(parts, ", ") or "none read"))
  local fill = {}
  for _, k in ipairs(ns.SortedKeys(data.equipFill)) do fill[#fill + 1] = k .. " " .. ns.fmt(data.equipFill[k]) end
  if #fill > 0 then add("  (read from Equip: text: " .. table.concat(fill, ", ") .. ")") end
  if (data.equipUnread or 0) > 0 then
    add("  " .. data.equipUnread .. " Equip: effect(s) aren't plain stats and weren't counted"
      .. " (procs, form-only attack power, one-school spell damage...)")
  end
  add("Missing: " .. (#data.missing > 0 and table.concat(data.missing, ", ") or "nothing"))
  add("Game language: " .. tostring(data.locale) .. (data.locale and not data.locale:find("^en") and
    " (Equip and set-bonus stats are read in English plus a few of the game's own strings)" or ""))
  return lines
end

-- Every equipped item's raw stats, for checking the stat names Forever uses.
function ns.ItemLines()
  local lines = {}
  local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
  for _, slot in ipairs(ns.SLOTS) do
    local link = ns.str(ns.try(GetInventoryItemLink, "player", slot))
    if link then
      local t = ns.try(fn, link)
      local parts = {}
      if type(t) == "table" then
        local keys = {}
        for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(ns.num(t[k]) or "?") end
      end
      lines[#lines + 1] = "slot " .. slot .. " " .. (link:match("item:(%d+)") or "?") .. ": "
        .. (#parts > 0 and table.concat(parts, " ") or "(no stats)")
    end
  end
  return lines
end

-- Raw API returns, for checking the addon against a real Forever client.
-- Secret values print as <secret>; nothing here is compared or added.
local function show(v)
  if ns.IsSecret(v) then return "<secret>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "string" then return '"' .. v:gsub("|", "||") .. '"' end
  if t == "number" or t == "boolean" then return tostring(v) end
  return "<" .. t .. ">"
end

local function packShow(...)
  local out = {}
  for i = 1, select("#", ...) do out[i] = show((select(i, ...))) end
  return table.concat(out, ", ")
end

local function raw(fn, ...)
  if type(fn) ~= "function" then return "(no such API)" end
  local res = { pcall(fn, ...) }
  if not res[1] then return "(error: " .. show(res[2]) .. ")" end
  return packShow(unpack(res, 2, table.maxn(res)))
end

function ns.DebugLines()
  local L = {}
  local function add(s) L[#L + 1] = s end
  add("SimBench " .. ns.VERSION .. " debug dump")
  if ns.lastError then add("Last export error: " .. show(ns.lastError)) end
  add("GetBuildInfo: " .. raw(GetBuildInfo))
  add("InCombatLockdown: " .. raw(InCombatLockdown) .. " | UnitAffectingCombat: " .. raw(UnitAffectingCombat, "player"))
  add("UnitClass: " .. raw(UnitClass, "player") .. " | UnitRace: " .. raw(UnitRace, "player")
    .. " | UnitFactionGroup: " .. raw(UnitFactionGroup, "player") .. " | UnitLevel: " .. raw(UnitLevel, "player"))
  add("GetNumTalentTabs: " .. raw(GetNumTalentTabs) .. " | GetNumTalents(1): " .. raw(GetNumTalents, 1))
  local SI = type(C_SpecializationInfo) == "table" and C_SpecializationInfo or {}
  add("C_SpecializationInfo: " .. (next(SI) and "present" or "absent")
    .. " | GetSpecializationInfo({specializationIndex=1}): " .. raw(SI.GetSpecializationInfo, { specializationIndex = 1 }))
  -- Trees are listed even without GetNumTalentTabs (Forever may not have it).
  for t = 1, 4 do
    add("C_SpecializationInfo.GetSpecializationInfo(" .. t .. "): " .. raw(SI.GetSpecializationInfo, t)
      .. " | GetNumTalents: " .. raw(GetNumTalents, t))
    local first = ns.try(SI.GetSpecializationInfo, t)
    if type(first) == "table" and not ns.IsSecret(first) then
      add("  (a table: name " .. show(first.name) .. ", pointsSpent " .. show(first.pointsSpent) .. ")")
    end
    add("  GetTalentTabInfo(" .. t .. "): " .. raw(GetTalentTabInfo, t))
    for i = 1, 2 do
      local info = ns.try(SI.GetTalentInfo, { specializationIndex = t, talentIndex = i })
      local fields = "(no such API)"
      if type(info) == "table" and not ns.IsSecret(info) then
        -- Every field, sorted, so differently named fields on a new client show up.
        local parts = {}
        for _, k in ipairs(ns.SortedKeys(info)) do parts[#parts + 1] = tostring(k) .. " " .. show(info[k]) end
        fields = table.concat(parts, ", ")
      elseif SI.GetTalentInfo then
        fields = show(info)
      end
      add("  C_SpecializationInfo.GetTalentInfo(" .. t .. "," .. i .. "): " .. fields
        .. " | GetTalentInfo: " .. raw(GetTalentInfo, t, i))
    end
  end
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  for _, slot in ipairs({ 0, 16, 17, 18 }) do
    local id = ns.num(ns.try(GetInventoryItemID, "player", slot))
    add("Slot " .. slot .. " GetInventoryItemID: " .. raw(GetInventoryItemID, "player", slot))
    if id then
      add("  GetItemInfoInstant: " .. raw(instant, id))
      local lines = ns.TooltipLines(slot == 0 and "item" or "inv", slot == 0 and id or slot) or {}
      for i, l in ipairs(lines) do
        if i > 8 then add("  ...") break end
        add("  tip " .. i .. ": " .. show(l.left) .. " | " .. show(l.right))
      end
    end
  end
  for bag = 1, 4 do
    local inv = (C_Container and ns.num(ns.try(C_Container.ContainerIDToInventoryID, bag))) or (19 + bag)
    local id = ns.num(ns.try(GetInventoryItemID, "player", inv))
    if id then add("Bag " .. bag .. " (inv " .. inv .. "): " .. raw(instant, id)) end
  end
  for i = 1, 5 do add("UnitStat(" .. i .. "): " .. raw(UnitStat, "player", i)) end
  add("UnitAttackPower: " .. raw(UnitAttackPower, "player") .. " | UnitRangedAttackPower: " .. raw(UnitRangedAttackPower, "player"))
  add("GetCritChance: " .. raw(GetCritChance) .. " | GetRangedCritChance: " .. raw(GetRangedCritChance)
    .. " | GetSpellCritChance(2): " .. raw(GetSpellCritChance, 2))
  add("GetHitModifier: " .. raw(GetHitModifier) .. " | GetSpellHitModifier: " .. raw(GetSpellHitModifier))
  add("UnitArmor: " .. raw(UnitArmor, "player"))
  add("Templates: DAMAGE " .. show(DAMAGE_TEMPLATE) .. " | SINGLE " .. show(SINGLE_DAMAGE_TEMPLATE)
    .. " | AMMO " .. show(AMMO_DAMAGE_TEMPLATE))
  add("Set templates: NAME " .. show(ITEM_SET_NAME) .. " | BONUS " .. show(ITEM_SET_BONUS)
    .. " | GRAY " .. show(ITEM_SET_BONUS_GRAY))
  -- The first set piece's full tooltip: set bonus wording is what most often
  -- needs mapping on a new client.
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  for _, slot in ipairs(ns.SLOTS) do
    local link = ns.str(ns.try(GetInventoryItemLink, "player", slot))
    local setID = link and ns.num(select(16, ns.try(info, link)))
    if setID and setID > 0 then
      add("Set piece in slot " .. slot .. " (set " .. setID .. "):")
      for i, l in ipairs(ns.TooltipLines("inv", slot) or {}) do
        if i > 30 then add("  ...") break end
        add("  tip " .. i .. ": " .. show(l.left) .. (l.right and (" | " .. show(l.right)) or ""))
      end
      break
    end
  end
  return L
end

-- One line saying whether a pasted string is complete.
function ns.VerifyText(text)
  local F, why = ns.Decode(text)
  if not F then return "|cffff5555String problem:|r " .. tostring(why) end
  local items = 0   -- equipped items, not counting ammo (slot 0)
  for part in (F.g or ""):gmatch("[^,]+") do if not part:find("^0:") then items = items + 1 end end
  -- Pasted text: cleaned so it can't carry chat codes into the window.
  return "|cff33ff33String is complete:|r " .. (ns.clean(F.cls) or "?") .. " level " .. (ns.clean(F.lvl) or "?")
    .. ", talents " .. (ns.clean(F.tal) or "none") .. ", " .. items .. " items."
end

local HELP = {
  "/simx - export gear, talents and stats for the sim (out of combat)",
  "/simx sim - the sim's web address (vulcanaddons.com/sim)",
  "/simx last - show the last export again",
  "/simx check - what this client supports and what an export reads",
  "/simx items - raw stats of each equipped item",
  "/simx verify - paste a string to check it's complete",
  "/simx button - show or hide the Sim button on the Character panel",
  "/simx debug - raw game data, for a bug report if something reads wrong",
}

function ns.Slash(msg)
  msg = ns.str(msg) or ""
  local cmd = msg:match("^%s*(%S*)")
  cmd = (cmd or ""):lower()
  if cmd == "" or cmd == "export" then
    ns.Export()
  elseif cmd == "sim" then
    ns.ShowSimURL()
  elseif cmd == "last" then
    local s = VulcanSimBenchCharDB and VulcanSimBenchCharDB.last
    if s then
      local notes = { "Your last export from this character." }
      for _, n in ipairs(VulcanSimBenchCharDB.lastNotes or {}) do notes[#notes + 1] = n end
      ns.ShowCopy(s, notes)
    else ns.Print("No export yet on this character. Type /simx.") end
  elseif cmd == "check" then
    for _, l in ipairs(ns.CheckLines()) do ns.Print(l) end
  elseif cmd == "items" then
    if ns.InCombat() then ns.Print("Leave combat first.") return end
    local lines = ns.ItemLines()
    ns.ShowCopy(table.concat(lines, "\n"), { "Raw item stats. Copy them into a bug report if a stat looks wrong." })
  elseif cmd == "debug" then
    if ns.InCombat() then ns.Print("Leave combat first.") return end
    ns.ShowCopy(table.concat(ns.DebugLines(), "\n"), { "Raw game data. Ctrl+C, then paste it into a bug report." })
  elseif cmd == "button" then
    local shown, exists = ns.ToggleCharacterButton()
    if not shown then ns.Print(exists and "Character-panel button hidden." or "Character-panel button turned off.")
    elseif exists then ns.Print("Character-panel button shown.")
    else ns.Print("Button turned on, but this client has no Character panel to put it on. Use /simx instead.") end
  elseif cmd == "verify" then
    -- Chat input stops at 255 characters and a full string is longer, so the
    -- check happens in a paste box instead.
    ns.ShowPaste(function(text) ns.SetBoxNotes({ ns.VerifyText(text) }) end,
      { "Paste a SimBench string here (Ctrl+V) to check it's complete." })
  else
    for _, l in ipairs(HELP) do ns.Print(l) end
  end
end

SLASH_VULCANSIMBENCH1 = "/simbench"
-- The names from before the Vulcan rename keep working.
SLASH_VULCANSIMBENCH2 = "/simx"
SLASH_VULCANSIMBENCH3 = "/simexport"
-- SlashCmdList always exists; assigning the global itself would taint it.
SlashCmdList.VULCANSIMBENCH = ns.Slash

function VulcanSimBench_OnAddonCompartmentClick()
  ns.Export()
end

-- Key binding (Options > Key Bindings > AddOns).
BINDING_HEADER_VULCANSIMBENCH = "Vulcan SimBench"
BINDING_NAME_VULCANSIMBENCH_EXPORT = "Export for the damage sim"
function VulcanSimBench_Export()
  ns.Export()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
  if name ~= ns.name then return end
  -- Saved-data safety (Persist.lua): look at what the client loaded before it's filled in.
  if ns.Persist then ns.Persist.CheckLoad(VulcanSimBenchDB, VulcanSimBenchCharDB) end
  VulcanSimBenchCharDB = VulcanSimBenchCharDB or {}
  ns.AddCharacterButton()
  if ns.Persist then ns.Persist.Warn() end
  self:UnregisterEvent("ADDON_LOADED")
end)
