-- Release checks: TOC fields, the version token, and the sim's web address.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local DIR = os.getenv("SX_DIR") or "../"

local function read(name)
  local f = assert(io.open(DIR .. name, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local toc = read("VulcanSimBench.toc")
H.check("TOC version is the packager token", toc:find("\n## Version: @project-version@\n", 1, true) ~= nil)
H.check("TOC author is Tavlius", toc:find("\n## Author: Tavlius\n", 1, true) ~= nil)
H.check("TOC title", toc:find("\n## Title: Vulcan SimBench\n", 1, true) ~= nil)
H.check("TOC interface is Forever 1.60.1 (16001)", toc:find("^## Interface: 16001\n") ~= nil)

-- Running from source the version is "dev": shown, and sent in the export as v=dev,
-- which the sim's decoder treats as "no hint" (it matches strings by format, FSX1).
do
  local h = H.boot()
  H.check("from source the version is dev", h.ns.VERSION == "dev", h.ns.VERSION)
  local s = h.ns.Export()
  local F = h.ns.Decode(s)
  H.check("an export from source carries v=dev and the format", F and F.v == "dev" and s:find("^FSX1:") ~= nil, F and F.v)
end
do
  _G.GetAddOnMetadata = function(_, field) if field == "Version" then return "v1.2.0" end end
  local h = H.boot()
  H.check("a release reads its tag (v1.2.0 shown as 1.2.0)", h.ns.VERSION == "1.2.0", h.ns.VERSION)
  _G.GetAddOnMetadata = function(_, field) if field == "Version" then return "@project-version@" end end
  local h2 = H.boot()
  H.check("the raw token is never shown or exported", h2.ns.VERSION == "dev", h2.ns.VERSION)
  _G.GetAddOnMetadata = nil
end

-- Where the sim is: its web address, ready to copy. (The sim isn't part of this
-- add-on: no page ships in it.)
do
  local h = H.boot()
  local url = h.ns.ShowSimURL()
  H.check("the sim's address is https://vulcanaddons.com/sim", url == "https://vulcanaddons.com/sim", url)
  local box = h.ns.CopyFrame()
  H.check("the address opens in the copy box", box and box.text == url)
  h.ns.ShowCopy("something else")   -- so the check below can't pass on what's already shown
  H.slash("sim")
  H.check("/simbench sim shows it", h.ns.CopyFrame().text == url, h.ns.CopyFrame().text)
  H.check("the export window has a 'Where's the sim?' button", box.simButton ~= nil)
  H.check("no sim page ships in the add-on", io.open(DIR .. "Sim/VulcanSimBench.html", "rb") == nil)
  -- With no notes, the line under the string says where to paste it.
  h.ns.ShowCopy("FSX1:x")
  local note = h.ns.CopyFrame().note.text or ""
  H.check("the export window says where to paste (the site)", note:find("vulcanaddons.com/sim", 1, true) ~= nil, note)
end

H.finish("SimBench release")
