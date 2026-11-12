local Loc = TREQ("scripts.locale")
local UI = TREQ("scripts.ui")

assert(Loc("ui-recorded", "42 s", "10 min")[1] == "production-flow.ui-recorded")
assert(LOC(Loc("ui-recorded", "42 s", "10 min")) == "Recorded 42 s / 10 min")
assert(LOC(Loc("material-count", 1)) == "1 material")
assert(LOC(Loc("material-count", 2)) == "2 materials")
assert(LOC(Loc("input-step-count", 1)) == "1 step")
assert(LOC(Loc("input-step-count", 6)) == "6 steps")
assert(LOC(Loc("group-item-count", "Example", 1)) == "Example (1 item)")
assert(LOC(Loc("group-fluid-count", "Example", 2)) == "Example (2 fluids)")

-- Reordering parameters is a catalog operation; runtime data is language neutral.
local factory = dofile(TESTDIR .. "/locale_test_support.lua")
local alternate = factory({ ["production-flow.ui-recorded"] = "__2__ / __1__ recorded" })
local message = Loc("ui-recorded", "42 s", "10 min")
assert(alternate(message) == "10 min / 42 s recorded")
assert(LOC(message) == "Recorded 42 s / 10 min" and getmetatable(message) == nil)

-- Rich strings nest safely beyond Factorio's 20-parameter boundary.
local parts = {}
for i = 1, 501 do parts[i] = Loc("input-step-count", i) end
local joined = Loc.join_list(parts, "; ")
local rendered = LOC(joined)
assert(rendered:sub(1, 7) == "1 step;" and rendered:find("501 steps", 1, true))
assert(Loc.join("ssk_", "frame", 2) == "ssk_frame2", "IDs must remain plain strings")

local Surfaces = TREQ("scripts.surfaces")
local planet = setmetatable({ name = "nauvis", prototype = { localised_name = { "space-location-name.nauvis" } } },
  { __index = function(_, key) error("Unsupported LuaPlanet property: " .. key) end })
local surface = { valid = true, name = "nauvis", planet = planet }
assert(Surfaces.localised(surface)[2] == planet.prototype.localised_name)
assert(Surfaces.label(surface) == "Nauvis", "Export/sort labels remain plain strings")
local platform = { valid = true, name = "internal-platform", platform = { valid = true, name = "My ship" } }
assert(Surfaces.localised(platform)[2] == "My ship" and Surfaces.label(platform) == "My ship")

-- Exercise GUI sinks without flattening their prototype LocalisedStrings.
local function check(element)
  if element.caption ~= nil then LOC(element.caption) end
  if element.tooltip ~= nil then LOC(element.tooltip) end
  for _, value in ipairs(element.items or {}) do LOC(value) end
  for _, child in ipairs(element.children) do check(child) end
end
for _, player in pairs(game.players) do
  UI.open(player)
  check(player.gui.screen.ssk_main)
end
print("LOCALIZATION LUA PASS: native tables, reordered parameters, plurals, long joins and GUI sinks")
