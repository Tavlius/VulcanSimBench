-- Saved-data safety (Persist.lua): a character file that didn't load is spotted and warned about.
package.path = "./?.lua;" .. package.path
local H = require("harness")

local function warned(h) return h.printedMatch("saved data didn't load") ~= nil end

-- A first login and a normal logout: the marker the cross-check needs.
local function firstInstall(opts)
  local h = H.boot(opts)
  return h, h.logout()
end

do
  local h, saved = firstInstall()
  H.check("first install: no failure", h.ns.Persist.failure == nil and not warned(h))
  H.check("logout lists this character in the account marker", type(saved.marker) == "table"
    and type(saved.marker.chars) == "table" and type(saved.marker.chars["Tavlius-Emberfall"]) == "number")
  local h2 = H.boot({ saved = saved.char, marker = saved.marker })
  H.check("normal reload: no failure, no warning", h2.ns.Persist.failure == nil and not warned(h2))
  local check = table.concat(h2.ns.CheckLines(), "\n")
  H.check("/simx check says saved data loaded", check:find("Saved data: loaded normally", 1, true) ~= nil, check)
end

do
  local _, saved = firstInstall()
  local h = H.boot({ marker = saved.marker })
  H.check("character load failure detected", h.ns.Persist.failure and h.ns.Persist.failure.char)
  H.check("warned in chat", warned(h))
  H.check("warned on screen", h.c.uiErrors[1] and h.c.uiErrors[1]:find("saved data didn't load", 1, true) ~= nil)
  H.check("says it's a known Forever client problem", h.printedMatch("known problem with the World of Warcraft: Forever client") ~= nil)
  H.check("says the next save overwrites the file", h.printedMatch("overwrite it the next time you log out or /reload") ~= nil)
  H.check("not silently empty: works on, with the warning", type(VulcanSimBenchCharDB) == "table" and warned(h))
  local check = table.concat(h.ns.CheckLines(), "\n")
  H.check("/simx check reports it", check:find("didn't load this session", 1, true) ~= nil, check)
end

do
  local _, saved = firstInstall()
  local a = H.boot({ marker = saved.marker, name = "Mirel" })
  H.check("new character on the account: no warning", a.ns.Persist.failure == nil and not warned(a))
  local b = H.boot({ marker = saved.marker, realm = false })
  H.check("realm unreadable: no guess, no warning", b.ns.Persist.failure == nil and not warned(b))
  local d = H.boot()
  H.check("both missing looks like a first install", d.ns.Persist.failure == nil and not warned(d))
  local e = H.boot({ marker = { chars = "junk" } })
  H.check("damaged marker: ignored", e.ns.Persist.failure == nil)
  local s = e.logout()
  H.check("damaged marker replaced at logout", type(s.marker.chars) == "table" and s.marker.chars["Tavlius-Emberfall"] ~= nil)
end

do
  -- The realm can be unreadable while the game loads: the check waits for login.
  local _, saved = firstInstall()
  local h = H.boot({ marker = saved.marker, realm = false })
  H.check("realm unreadable at load: no verdict yet", h.ns.Persist.failure == nil and not warned(h))
  _G.GetNormalizedRealmName = function() return "Emberfall" end
  for _, f in ipairs(h.c.frames) do
    if f.events.PLAYER_LOGIN and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
  end
  H.check("realm readable at login: the failure is caught then", h.ns.Persist.failure ~= nil and warned(h))

  -- A new character on the account, same timing: still not a failure.
  local n = H.boot({ marker = saved.marker, name = "Mirel", realm = false })
  _G.GetNormalizedRealmName = function() return "Emberfall" end
  for _, f in ipairs(n.c.frames) do
    if f.events.PLAYER_LOGIN and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
  end
  H.check("late check: a new character is still not a failure", n.ns.Persist.failure == nil and not warned(n))
end

H.finish("SimBench persist")
