-- SimBench: shared helpers (secret-value safety, rounding, checksum, text patterns).
local ADDON_NAME, ns = ...
ns.name = ADDON_NAME
-- The version from the TOC, where the packager writes the release tag ("v1.2.0" is
-- shown and exported as "1.2.0"). Running from source it's still the
-- "@project-version@" token, so it's "dev". The sim matches exports by FORMAT,
-- never by this; it only uses the version for an "export again" hint.
do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or error, ADDON_NAME, "Version")
  ns.VERSION = ok and type(v) == "string" and v:match("^v?(%d+%.%d+[%w%.%-]*)$") or "dev"
end
-- Vulcan Suite accent ("ember"), shared by all four add-ons: chat name, titles, borders.
ns.ACCENT = { 0.91, 0.47, 0.17 }
ns.ACCENT_CODE = "|cffe8792b"
ns.FORMAT = "FSX1"   -- bump when the string layout changes; the sim's decoder checks it

---------------------------------------------------------------------------
-- Secret values. Forever uses Midnight's addon rules: some values come back
-- "secret" and throw if compared, added or printed. The secret check must run
-- before anything else touches the value (even `v == nil` can throw).
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
ns.IsSecret = issecret

-- A plain Lua number, or nil (secret, missing, NaN or infinite).
function ns.num(v)
  if issecret(v) then return nil end
  if type(v) ~= "number" then return nil end
  if v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- A plain Lua string, or nil.
function ns.str(v)
  if issecret(v) then return nil end
  if type(v) ~= "string" then return nil end
  return v
end

-- Calls fn(...) and returns its results, or nothing if the API is missing or errors.
function ns.try(fn, ...)
  if type(fn) ~= "function" then return end
  local res = { pcall(fn, ...) }
  if not res[1] then return end
  return unpack(res, 2, table.maxn(res))
end

function ns.Print(msg)
  print(ns.ACCENT_CODE .. "SimBench|r: " .. tostring(msg))
end

-- A map's keys, sorted (so output order never depends on hash order).
function ns.SortedKeys(map)
  local keys = {}
  for k in pairs(map or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Rounds to `places` decimals and drops trailing zeros: 2.60 -> "2.6", 13 -> "13".
function ns.fmt(v, places)
  v = ns.num(v)
  if not v then return nil end
  local s = string.format("%." .. (places or 2) .. "f", v)
  if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
  if s == "-0" then s = "0" end
  return s
end

-- UTF-8 byte sequences: NBSP, U+2000-200A, U+2028/2029, U+202F, U+205F, U+3000;
-- and zero-width U+200B-200D, U+2060, U+FEFF.
ns.UNICODE_SPACES = { "\194\160", "\225\154\128", "\226\128[\128-\138]", "\226\128[\168\169\175]",
  "\226\129\159", "\227\128\128" }
ns.ZERO_WIDTH = { "\226\128[\139-\141]", "\226\129\160", "\239\187\191" }

-- Plain text from a game string: colour (|cff...|r, |cnIQ4:...|r), texture
-- (|T...|t), atlas (|A...|a) and link (|H...|h) codes removed. nil if not a string.
function ns.StripCodes(s)
  s = ns.str(s)
  if not s then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
  s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|n", " ")
  return s
end

-- Text safe to put inside a field: no separators the format uses and no
-- whitespace (spaces become "+"), since the decoder strips whitespace that
-- copying or line-wrapping can add. Not "_" or "*": Discord turns those into
-- italics and bold and drops them from copied text.
function ns.clean(s)
  s = ns.str(s)
  if not s then return nil end
  s = ns.StripCodes(s):gsub("[\t\r\n]", " ")   -- line breaks and tabs are spaces, not deleted
  -- Unicode spaces become plain spaces (the sim strips all whitespace, Unicode
  -- included, before checking the checksum); zero-width characters go.
  for _, u in ipairs(ns.UNICODE_SPACES) do s = s:gsub(u, " ") end
  for _, u in ipairs(ns.ZERO_WIDTH) do s = s:gsub(u, "") end
  -- Also no HTML-special characters, so a tree name can't carry markup to a page.
  s = s:gsub("[;=,:#|%c_%*~`+<>&\"]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "+")
  return s
end

-- Adler-32, as 8 lowercase hex digits. Catches a string cut off while copying.
-- (Matches the decoder in simx-decode.js; both work on bytes.)
function ns.Adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  -- Two 16-bit halves: "%x" on a value of 2^31 or more isn't safe in every
  -- Lua 5.1 build (it goes through a C long, 32 bits on Windows).
  return string.format("%04x%04x", b, a)
end

-- Turns a client format string (e.g. DAMAGE_TEMPLATE "%s - %s Damage") into a
-- Lua pattern that captures each %s / %d as a number. Locale-proof parsing.
-- With asText, %s captures any text instead (for "Set: %s" and "%s (%d/%d)").
-- %c (a "+" or "-" sign, as in "%c%d Agility") is matched but not captured.
function ns.TemplatePattern(template, asText)
  template = ns.str(template)
  if not template or template == "" then return nil end
  -- Positional forms like %1$s become plain %s.
  local t = template:gsub("%%%d+%$", "%%")
  local out, i = {}, 1
  while i <= #t do
    local c = t:sub(i, i)
    if c == "%" then
      local n = t:sub(i + 1, i + 1)
      if n == "s" and asText then
        out[#out + 1] = "(.-)"
        i = i + 2
      elseif n == "d" and asText then
        out[#out + 1] = "(%d+)"
        i = i + 2
      elseif n == "s" or n == "d" then
        out[#out + 1] = "([%d%.,]+)"
        i = i + 2
      elseif n == "c" then
        out[#out + 1] = "[%+%-]?"
        i = i + 2
      elseif n == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      elseif n == "." then
        -- %.1f style: skip to the conversion letter
        local j = t:find("[fgd]", i + 1)
        out[#out + 1] = "([%d%.,]+)"
        i = (j or i + 1) + 1
      else
        out[#out + 1] = "%%"
        i = i + 1
      end
    elseif c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then
      out[#out + 1] = "%" .. c
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return "^%s*" .. table.concat(out) .. "%s*$"
end

-- "2,60" (German decimal comma) or "1,234" (thousands) -> number.
function ns.ToNumber(s)
  s = ns.str(s)
  if not s then return nil end
  if s:find("^%d+,%d%d%d$") then s = s:gsub(",", "")      -- 1,234
  else s = s:gsub(",", ".") end                            -- 2,60
  return tonumber(s)
end
