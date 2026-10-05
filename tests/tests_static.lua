-- Static checks on the addon source.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local DIR = os.getenv("SX_DIR") or "../"
-- Lua files come from the TOC (load order), and the TOC must list every Lua file in the folder.
local toc = io.open(DIR .. "VulcanSimBench.toc"):read("*a")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
  if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
end
do
  local listed = {}
  for _, f in ipairs(files) do listed[f] = true end
  local p = io.popen('ls "' .. DIR .. '"')
  for f in p:lines() do
    if f:match("%.lua$") then H.check("toc lists " .. f, listed[f], f) end
  end
  p:close()
  H.check("toc has Lua files", #files >= 5, #files)
end
local LOCAL_HELPERS = { GetInstant = true, GetStatsTable = true, GetText = true }
for _, f in ipairs(files) do
  local n = 0
  for line in io.lines(DIR .. f) do
    n = n + 1
    if not line:match("^%s*%-%-") then
      -- Ignore text inside string literals ("GetCritChance: " is a label, not a call).
      local code = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
      for call in code:gmatch("%f[%w_]([%a_][%w_]*)%(") do
        local isApi = call:match("^Get%u") or call:match("^Unit%u") or call == "InCombatLockdown"
        local qualified = code:match("C_%w+%.%w+%(")
        if (isApi and not LOCAL_HELPERS[call] and not code:find("function", 1, true)) or qualified then
          -- ns.try and the debug dump's raw() both call through pcall.
          local safe = code:find("ns.try", 1, true) or code:find("raw(", 1, true)
          H.check(f .. ":" .. n .. " game API called directly (use ns.try)", safe, line)
        end
      end
    end
  end
end
-- No print() calls outside ns.Print (keeps chat output in one style).
for _, f in ipairs(files) do
  local n = 0
  for line in io.lines(DIR .. f) do
    n = n + 1
    if f ~= "Util.lua" and line:match("^%s*print%(") then H.check(f .. ":" .. n .. " bare print", false, line) end
  end
end
-- raw() must really be a pcall wrapper for the exemption above to be safe.
local cmd = io.open(DIR .. "Commands.lua"):read("*a")
local rawBody = cmd:match("local function raw%(fn, %.%.%.%)(.-)\nend")
H.check("raw() wraps calls in pcall", rawBody and rawBody:find("pcall(fn, ...)", 1, true), rawBody)

-- README documents every field and every slash command.
local readme = io.open(DIR .. "README.md"):read("*a")
local fmt = io.open(DIR .. "Format.lua"):read("*a")
local order = fmt:match("ns.FIELD_ORDER = {(.-)}")
for key in order:gmatch('"(%w+)"') do
  H.check("README documents field " .. key, readme:find("`" .. key .. "`", 1, true), key)
end
for sub in cmd:gmatch('"/simx (%l+)') do
  H.check("README documents /simx " .. sub, readme:find("/simx " .. sub, 1, true), sub)
end

H.check("Util loads first", files[1] == "Util.lua", files[1])
-- Version: the TOC holds the packager token; the code reads the TOC and says "dev"
-- while the token is unreplaced (running from source). No hard-coded release number.
local util = io.open(DIR .. "Util.lua"):read("*a")
H.check("TOC version is the packager token", toc:find("\n## Version: @project-version@\n", 1, true) ~= nil)
H.check("version is read from the TOC", util:find('GetAddOnMetadata', 1, true) ~= nil)
H.check("no hard-coded release number", not util:find('ns.VERSION = "%d') and not util:find('or "%d+%.%d+'))
-- Never reassign Blizzard globals (taint).
for _, f in ipairs(files) do
  local src = io.open(DIR .. f):read("*a")
  H.check(f .. " doesn't reassign SlashCmdList", not src:find("\nSlashCmdList%s*="), f)
end
-- Bindings.xml: balanced tags and the binding the TOC-loaded code defines.
local xml = io.open(DIR .. "Bindings.xml"):read("*a")
local opens, closes = 0, 0
for tag in xml:gmatch("<([^>]*)>") do
  if tag:match("^/") then closes = closes + 1 elseif not tag:match("/$") and not tag:match("^[?!]") then opens = opens + 1 end
end
H.check("Bindings.xml tags balance", opens == closes, opens .. " vs " .. closes)
H.check("per-character saved variables", toc:find("SavedVariablesPerCharacter: VulcanSimBenchCharDB", 1, true))
-- The one account-wide file is the saved-data safety marker (Persist.lua): a character list only.
H.check("account-wide file is only the safety marker", toc:find("\n## SavedVariables: VulcanSimBenchDB\n", 1, true))
H.finish("SimBench static")
