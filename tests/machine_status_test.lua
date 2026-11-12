package.path = "./?.lua;" .. package.path

local status = { item_ingredient_shortage = 1, fluid_ingredient_shortage = 2, no_ingredients = 3,
  full_output = 4, no_power = 5, low_power = 6, no_fuel = 7, working = 8, disabled_by_script = 9 }
defines = { entity_status = status }
settings = { global = { ["ssk-window-seconds"] = { value = 60 }, ["ssk-entities-per-tick"] = { value = 2 } } }
local nauvis, other = { index = 1, name = "nauvis", valid = true }, { index = 2, name = "other", valid = true }
game = { tick = 0, surfaces = { nauvis, other } }
storage = {}
local Sm = require("scripts.sampler")
local StatusUI = require("scripts.machine_status_ui")
Sm.init()

local machines, status_reads = {}, 0
local function machine(recipe, state, surface, force, furnace)
  local e = setmetatable({ valid = true, type = furnace and "furnace" or "assembling-machine",
    unit_number = #machines + 1, products_finished = 0, crafting_speed = 1,
    surface = surface, surface_index = surface.index, force_index = force,
    position = { x = #machines * 4, y = 0 }, recipe = recipe, state = state }, {
    __index = function(self, key)
      if key == "status" then status_reads = status_reads + 1; return self.state end
    end,
  })
  e.get_recipe = function() if e.recipe and not furnace then return { name = e.recipe } end end
  if furnace then e.previous_recipe = { name = { name = recipe } } end
  machines[#machines + 1] = e
  Sm.add(e)
  return e
end

local starved = machine("iron-plate", status.no_ingredients, nauvis, 1, true)
local no_power = machine("iron-plate", status.no_power, nauvis, 1)
local no_fuel = machine("iron-plate", status.no_fuel, nauvis, 1)
local blocked = machine("gear", status.full_output, nauvis, 1)
local disabled = machine("gear", status.disabled_by_script, nauvis, 1)
machine("iron-plate", status.item_ingredient_shortage, nauvis, 2)
machine("iron-plate", status.fluid_ingredient_shortage, other, 1)

local function advance(tick)
  for t = game.tick + 1, tick do game.tick = t; Sm.on_tick(t) end
end

-- Same-version source replacement can load a save without configuration change.
storage.machine_status = nil
storage.mcursor = 3
assert(select(2, Sm.machine_status(1, 1)), "pre-existing registry should start warming")
advance(3)
assert(select(2, Sm.machine_status(1, 1)), "a partial old cycle must not complete warm-up")
advance(10)
local rows, warming = Sm.machine_status(1, 1)
assert(not warming and status_reads == #machines, "sample all machines once while the first pass fills")
assert(rows["iron-plate"].observed == 3 and rows["iron-plate"].issues.input.count == 1)
assert(rows["iron-plate"].issues.power.count == 2 and rows.gear.issues.output.count == 1)
assert(rows.gear.observed == 2 and not rows.gear.issues.power and not rows.gear.issues.input)
assert(Sm.machine_status(1, 2)["iron-plate"].issues.input.count == 1, "force isolation")
assert(Sm.machine_status(2, 1)["iron-plate"].issues.input.count == 1, "surface isolation")
assert(Sm.find_status_machine(1, 1, "iron-plate", "input") == starved, "furnace previous recipe")
advance(100)
assert(status_reads == #machines + 1, "normal visits must not reread status inside five seconds")

-- Issue targets are live-checked even before the next sampled observation.
local preferred = Sm.find_status_machine(1, 1, "iron-plate", "power")
preferred.state = status.working
assert(Sm.find_status_machine(1, 1, "iron-plate", "power") == (preferred == no_power and no_fuel or no_power))
assert(rows["iron-plate"].issues.power.count == 2, "live lookup must not mutate counts")
preferred.state = status.low_power
disabled.force_index, disabled.surface_index, disabled.surface = 2, 2, other
disabled.recipe, disabled.state = "iron-plate", status.low_power
advance(105)
assert(rows.gear.observed == 1, "recipe transition should remove the previous observation promptly")
assert(Sm.machine_status(2, 2)["iron-plate"].issues.power.count == 1)
disabled.valid = false
advance(110)
assert(not Sm.machine_status(2, 2), "drop invalid entities and prune emptied scope")

local function element(spec, parent)
  local e = { children = {}, style = {}, valid = true, tags = {}, visible = true, parent = parent }
  for k, v in pairs(spec) do if k ~= "style" then e[k] = v end end
  setmetatable(e, { __index = function(self, key)
    for _, child in ipairs(self.children) do if child.valid and child.name == key then return child end end
  end })
  e.add = function(child)
    local added = element(child, e)
    e.children[#e.children + 1] = added
    return added
  end
  e.destroy = function() e.valid = false end
  return e
end

local function find(e, field, value)
  if e.valid and e.tags[field] == value then return e end
  for _, child in ipairs(e.children) do
    local found = find(child, field, value)
    if found then return found end
  end
end

storage.graph = { nodes = { ["item/iron-plate"] = { type = "item", name = "iron-plate",
  producers = { "iron-plate", "iron-plate" }, consumers = { "gear" } } } }
prototypes = { item = {}, recipe = {} }
local screen = element {}
local main = screen.add { name = "ssk_main" }
local player = { gui = { screen = screen }, force_index = 1, opened = main,
  display_resolution = { width = 1024, height = 768 }, display_scale = 2 }
local status_window = StatusUI.open(player, 1, "item/iron-plate")
local sample = find(status_window, "ssk_machine_age", "iron-plate")
assert(sample and LOC(sample.caption) == "1 s" and sample.tags.sample_tick < game.tick)
assert(find(status_window, "ssk_machine_age", "gear"), "show observed consumer recipes")
local inspect = find(status_window, "ssk_machine_status", "preview")
assert(inspect and inspect.tags.issue == "input" and not inspect.caption)
assert(LOC(inspect.parent.ssk_machine_count.caption) == "1", "the count is readable beside its preview action")
assert(StatusUI.on_click(player, inspect) and screen.ssk_machine_preview and not status_window.visible)
local preview = screen.ssk_machine_preview
local slider = find(preview, "ssk_machine_status", "zoom")
slider.slider_value = 1.25
assert(StatusUI.on_value_changed(player, slider))
local camera = slider.parent.parent.ssk_machine_camera
assert(camera.type == "camera" and camera.zoom == 1.25 and camera.surface_index == 1 and camera.position == starved.position)
assert(StatusUI.on_closed(player, main) and not screen.ssk_machine_preview and status_window.visible)
assert(player.opened == main and main.valid, "Esc closes preview first")
assert(StatusUI.on_click(player, inspect) and screen.ssk_machine_preview)
local jump = find(screen.ssk_machine_preview, "ssk_machine_status", "jump")
starved.state = status.working
assert(StatusUI.on_click(player, jump, function() error("stale target closed the main window") end))
assert(not screen.ssk_machine_preview and main.valid and not player.centered_on)
assert(status_window.ssk_machine_panel.ssk_machine_notice.visible)
assert(StatusUI.on_click(player, inspect) and not screen.ssk_machine_preview, "revalidate before preview")
starved.state = status.no_ingredients
assert(StatusUI.on_click(player, inspect))
jump = find(screen.ssk_machine_preview, "ssk_machine_status", "jump")
assert(StatusUI.on_click(player, jump, function(p) StatusUI.close(p); main.destroy() end))
assert(player.centered_on == starved and not main.valid and not screen.ssk_machine_status and not screen.ssk_machine_preview)

starved.state = status.working
blocked.state = status.low_power
advance(320)
assert(not rows["iron-plate"].issues.input and not rows.gear.issues.output)
assert(rows.gear.issues.power.count == 1 and rows.gear.sample_tick >= 300)
print("MACHINE STATUS OK: warm-up, cadence, recipe and scope changes, preview, zoom, Esc and jump")
