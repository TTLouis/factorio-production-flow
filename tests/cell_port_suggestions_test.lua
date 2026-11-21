-- Unit tests for single-selection port auto-config (recipe topology + physical
-- boundary confirmation) and cell outlines (stops, buffers, chart render mode).
local PortSuggestions = require("scripts.cell_port_suggestions")
local Outlines = require("scripts.cell_outlines")

-- Minimal Factorio globals for offline testing.
defines = defines or {}
defines.direction = defines.direction or { north = 0, east = 4, south = 8, west = 12 }
defines.inventory = defines.inventory or { chest = 1 }
game = game or { forces = { player = { name = "player" } }, surfaces = {} }
storage = storage or {}
storage.graph = {
  recipes = {
    ["copper-cable"] = {
      energy = 0.5,
      ingredients = { { key = "item/copper-plate", amount = 1 } },
      products = { { key = "item/copper-cable", amount = 2, prod = 2 } },
    },
    ["electronic-circuit"] = {
      energy = 0.5,
      ingredients = { { key = "item/iron-plate", amount = 1 }, { key = "item/copper-cable", amount = 3 } },
      products = { { key = "item/electronic-circuit", amount = 1, prod = 1 } },
    },
    ["kovarex"] = {
      energy = 60,
      ingredients = { { key = "item/uranium-235", amount = 40 }, { key = "item/uranium-238", amount = 5 } },
      products = { { key = "item/uranium-235", amount = 41, prod = 1 }, { key = "item/uranium-238", amount = 2, prod = 0 } },
    },
    ["heavy-oil-cracking"] = {
      energy = 2,
      ingredients = { { key = "fluid/heavy-oil", amount = 40 }, { key = "fluid/water", amount = 30 } },
      products = { { key = "fluid/light-oil", amount = 30, prod = 30 } },
    },
    ["advanced-oil-processing"] = {
      energy = 5,
      ingredients = { { key = "fluid/crude-oil", amount = 100 }, { key = "fluid/water", amount = 50 } },
      products = {
        { key = "fluid/heavy-oil", amount = 25, prod = 25 },
        { key = "fluid/light-oil", amount = 45, prod = 45 },
        { key = "fluid/petroleum-gas", amount = 55, prod = 55 },
      },
    },
  },
}

-- 1. Overbuilt and underbuilt internal intermediates stay excluded by default.
do
  local rates = { ["copper-cable"] = { normal = 2, bonus = 0 }, ["electronic-circuit"] = { normal = 1, bonus = 0 } }
  local net = { ["item/copper-plate"] = -2, ["item/iron-plate"] = -1, ["item/copper-cable"] = 1, ["item/electronic-circuit"] = 1 }
  local produced = { ["item/copper-cable"] = 4, ["item/electronic-circuit"] = 1 }
  local consumed = { ["item/copper-plate"] = true, ["item/iron-plate"] = true, ["item/copper-cable"] = true }
  local ports = PortSuggestions.suggest(net, produced, consumed, rates, {})
  assert(ports.inputs["item/copper-plate"] and ports.inputs["item/iron-plate"])
  assert(ports.outputs["item/electronic-circuit"])
  assert(not ports.inputs["item/copper-cable"] and not ports.outputs["item/copper-cable"],
    "Overbuilt copper cable stays internal by default")

  -- Underbuilt copper cable also stays internal by default.
  net["item/copper-cable"] = -1
  ports = PortSuggestions.suggest(net, produced, consumed, rates, {})
  assert(not ports.inputs["item/copper-cable"] and not ports.outputs["item/copper-cable"],
    "Underbuilt copper cable stays internal by default")
end

-- 2. Cycle / catalyst (Kovarex) keeps net output U-235 and net input U-238.
do
  local rates = { ["kovarex"] = { normal = 1, bonus = 0 } }
  local net = { ["item/uranium-235"] = 1, ["item/uranium-238"] = -3 }
  local produced = { ["item/uranium-235"] = 41, ["item/uranium-238"] = 2 }
  local consumed = { ["item/uranium-235"] = true, ["item/uranium-238"] = true }
  local ports = PortSuggestions.suggest(net, produced, consumed, rates, {})
  assert(ports.outputs["item/uranium-235"] and not ports.inputs["item/uranium-235"], "Kovarex exports U-235")
  assert(ports.inputs["item/uranium-238"] and not ports.outputs["item/uranium-238"], "Kovarex imports U-238")
end

-- 3. Physical boundary confirmation: belts, logistic chests, pumps.
do
  local area = { left_top = { x = 0, y = 0 }, right_bottom = { x = 10, y = 10 } }
  local function belt_line(items)
    return { valid = true, get_contents = function() return items end }
  end
  local out_belt = {
    valid = true, type = "transport-belt", position = { x = 10, y = 5 },
    belt_neighbours = { inputs = { { valid = true, position = { x = 9, y = 5 } } }, outputs = { { valid = true, position = { x = 11, y = 5 } } } },
    get_max_transport_line_index = function() return 1 end,
    get_transport_line = function() return belt_line({ { name = "copper-cable", count = 4 }, { name = "stone", count = 2 } }) end,
  }
  local surface = {
    find_entities_filtered = function(filter)
      if type(filter.type) == "table" and filter.type[1] == "transport-belt" then return { out_belt } end
      return {}
    end,
  }
  local rates = { ["copper-cable"] = { normal = 2, bonus = 0 }, ["electronic-circuit"] = { normal = 1, bonus = 0 } }
  local net = { ["item/copper-plate"] = -2, ["item/iron-plate"] = -1, ["item/copper-cable"] = 1, ["item/electronic-circuit"] = 1 }
  local produced = { ["item/copper-cable"] = 4, ["item/electronic-circuit"] = 1 }
  local consumed = { ["item/copper-plate"] = true, ["item/iron-plate"] = true, ["item/copper-cable"] = true }
  local ports = PortSuggestions.suggest(net, produced, consumed, rates, {}, surface, area)
  assert(ports.outputs["item/copper-cable"], "Outgoing boundary belt promotes copper-cable to output")
  assert(not ports.outputs["item/stone"] and not ports.inputs["item/stone"], "Unrelated pass-through item is ignored")

  -- Incoming requester chest promotes intermediate to input.
  local req_chest = {
    valid = true, type = "logistic-container", position = { x = 5, y = 5 },
    prototype = { logistic_mode = "requester" },
    get_logistic_sections = function()
      return { valid = true, sections = { { valid = true, active = true, filters = { { value = { name = "copper-cable" }, min = 100 } } } } }
    end,
  }
  local surface_req = {
    find_entities_filtered = function(filter)
      if filter.type == "logistic-container" then return { req_chest } end
      return {}
    end,
  }
  ports = PortSuggestions.suggest(net, produced, consumed, rates, {}, surface_req, area)
  assert(ports.inputs["item/copper-cable"] and not ports.outputs["item/copper-cable"],
    "Requester chest promotes copper-cable to input")

  -- Outgoing pump promotes heavy-oil intermediate to output.
  local out_pump = {
    valid = true, type = "pump", position = { x = 10, y = 5 }, direction = defines.direction.east,
    fluidbox_neighbours = { { { valid = true, position = { x = 11, y = 5 } } } },
    get_fluid_contents = function() return { ["heavy-oil"] = 200 } end,
  }
  local surface_pump = {
    find_entities_filtered = function(filter)
      if type(filter.type) == "table" and filter.type[1] == "pipe" then return { out_pump } end
      return {}
    end,
  }
  local oil_rates = { ["advanced-oil-processing"] = { normal = 1, bonus = 0 }, ["heavy-oil-cracking"] = { normal = 0.5, bonus = 0 } }
  local oil_net = { ["fluid/crude-oil"] = -100, ["fluid/water"] = -65, ["fluid/heavy-oil"] = 5, ["fluid/light-oil"] = 60, ["fluid/petroleum-gas"] = 55 }
  local oil_prod = { ["fluid/heavy-oil"] = 25, ["fluid/light-oil"] = 60, ["fluid/petroleum-gas"] = 55 }
  local oil_cons = { ["fluid/crude-oil"] = true, ["fluid/water"] = true, ["fluid/heavy-oil"] = true }
  ports = PortSuggestions.suggest(oil_net, oil_prod, oil_cons, oil_rates, {}, surface_pump, area)
  assert(ports.outputs["fluid/heavy-oil"], "Outgoing pump promotes heavy-oil to output")
end

-- 4. Outlines draw paired game + chart objects for machines, stops and buffers.
do
  local drawn = {}
  rendering = {
    draw_rectangle = function(spec)
      local obj = { valid = true, kind = "rect", spec = spec }
      obj.destroy = function() obj.valid = false end
      drawn[#drawn + 1] = obj
      return obj
    end,
    draw_text = function(spec)
      local obj = { valid = true, kind = "text", spec = spec }
      obj.destroy = function() obj.valid = false end
      drawn[#drawn + 1] = obj
      return obj
    end,
  }
  game.surfaces[1] = { index = 1 }
  local player = { index = 1 }
  local machine = { valid = true, position = { x = 2, y = 2 }, tile_width = 3, tile_height = 3,
    selection_box = { left_top = { x = 0.5, y = 0.5 }, right_bottom = { x = 3.5, y = 3.5 } } }
  local stop_ent = { valid = true, position = { x = 10, y = 2 },
    selection_box = { left_top = { x = 9, y = 1 }, right_bottom = { x = 11, y = 3 } } }
  local buf_ent = { valid = true, position = { x = 12, y = 2 },
    selection_box = { left_top = { x = 11.5, y = 1.5 }, right_bottom = { x = 12.5, y = 2.5 } } }
  local draft = {
    name = "Circuits", surface_index = 1,
    members = { [101] = machine },
    stops = { [201] = { entity = stop_ent, name = "Stop", role = "export", buffers = { [301] = buf_ent } } },
  }
  local shown = Outlines.show_draft(player, draft, 1)
  local game_rects, chart_rects, game_texts, chart_texts = 0, 0, 0, 0
  for _, obj in ipairs(shown.objects) do
    if obj.kind == "rect" then
      if obj.spec.render_mode == "game" then game_rects = game_rects + 1
      elseif obj.spec.render_mode == "chart" then chart_rects = chart_rects + 1 end
    elseif obj.kind == "text" then
      if obj.spec.render_mode == "game" then game_texts = game_texts + 1
      elseif obj.spec.render_mode == "chart" then chart_texts = chart_texts + 1 end
    end
  end
  -- 3 live entities (machine + stop + buffer) * 2 (fill + border) = 6 per render_mode
  assert(game_rects == 6 and chart_rects == 6, "Expected 6 game and 6 chart rects, got " .. game_rects .. "/" .. chart_rects)
  assert(game_texts == 1 and chart_texts == 1, "Expected 1 game and 1 chart label")
  local old_sig = shown.sig
  draft.stops[201].buffers[302] = buf_ent
  local updated = Outlines.show_draft(player, draft, 1)
  assert(updated.sig ~= old_sig, "Adding a buffer updates the outline signature")

  -- show_surface outlines all registered cells on the current surface (excluding an edited cell).
  local records = {
    [1] = { id = 1, name = "A", surface_index = 1, members = { [101] = machine }, positions = { [101] = { x = 2, y = 2, w = 3, h = 3 } } },
    [2] = { id = 2, name = "B", surface_index = 1, members = { [102] = machine }, positions = { [102] = { x = 6, y = 2, w = 3, h = 3 } } },
    [3] = { id = 3, name = "Other", surface_index = 2, members = { [103] = machine }, positions = { [103] = { x = 2, y = 2, w = 3, h = 3 } } },
  }
  local cursor_shown = Outlines.show_surface(player, records, 1, 1)
  assert(cursor_shown and Outlines.current(player.index, "cursor") == cursor_shown,
    "show_surface populates the cursor outline slot")
  assert(cursor_shown.sig:find("2@1=B", 1, true) and not cursor_shown.sig:find("1@1=A", 1, true)
    and not cursor_shown.sig:find("3@2=Other", 1, true),
    "show_surface includes only other cells on the current surface")
  Outlines.clear(player.index)
end

print("CELL PORT SUGGESTIONS & OUTLINES PASS")
