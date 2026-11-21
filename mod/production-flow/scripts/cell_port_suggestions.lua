local Model = require("scripts.model")

local PortSuggestions = {}
local EPSILON = 1e-9

local BELT_TYPES = { "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1" }
local FLUID_TYPES = { "pipe", "pipe-to-ground", "pump" }

local function inside(area, pos)
  if not (area and pos) then return false end
  local lt, rb = area.left_top or area[1], area.right_bottom or area[2]
  if not (lt and rb) then return false end
  local x1, y1 = lt.x or lt[1], lt.y or lt[2]
  local x2, y2 = rb.x or rb[1], rb.y or rb[2]
  return pos.x >= x1 and pos.x <= x2 and pos.y >= y1 and pos.y <= y2
end

local function has_outside(list, area)
  for _, neighbour in ipairs(list or {}) do
    if neighbour and neighbour.valid and not inside(area, neighbour.position) then return true end
  end
  return false
end

-- Unit vector for cardinal pump directions (Factorio 2.0/2.1 defines.direction uses 16 steps).
local function direction_vector(dir)
  local d = defines and defines.direction
  if not d then return 0, 0 end
  if dir == d.north then return 0, -1
  elseif dir == d.east then return 1, 0
  elseif dir == d.south then return 0, 1
  elseif dir == d.west then return -1, 0 end
  return 0, 0
end

local function scan_boundary(surface, area, relevant, net)
  local boundary_in, boundary_out, pipe_boundary = {}, {}, {}
  if not (surface and area and surface.find_entities_filtered and next(relevant)) then
    return boundary_in, boundary_out, pipe_boundary
  end
  local force = game and game.forces and game.forces.player
  if not force then return boundary_in, boundary_out, pipe_boundary end

  -- 1. Transport belts, undergrounds, splitters and loaders crossing the selection border.
  for _, entity in ipairs(surface.find_entities_filtered { area = area, type = BELT_TYPES, force = force }) do
    if entity.valid then
      local bn = entity.belt_neighbours
      local from_outside = bn and has_outside(bn.inputs, area) or false
      local to_outside = bn and has_outside(bn.outputs, area) or false
      if entity.type == "underground-belt" then
        local pair = entity.underground_belt_neighbour
        if pair and pair.valid and not inside(area, pair.position) then
          if entity.belt_to_ground_type == "output" then from_outside = true
          elseif entity.belt_to_ground_type == "input" then to_outside = true end
        end
      end
      if from_outside or to_outside then
        local max_lines = entity.get_max_transport_line_index and entity.get_max_transport_line_index() or 0
        for i = 1, max_lines do
          local line = entity.get_transport_line(i)
          if line and line.valid then
            for _, stack in ipairs(line.get_contents() or {}) do
              if (stack.count or 0) > 0 then
                local key = "item/" .. stack.name
                if relevant[key] then
                  if from_outside then boundary_in[key] = true end
                  if to_outside then boundary_out[key] = true end
                end
              end
            end
          end
        end
      end
    end
  end

  -- 2. Logistic containers inside the selection (requester/buffer -> input, provider -> output).
  for _, entity in ipairs(surface.find_entities_filtered { area = area, type = "logistic-container", force = force }) do
    if entity.valid then
      local mode = entity.prototype and entity.prototype.logistic_mode
      if mode == "requester" or mode == "buffer" then
        local sections = entity.get_logistic_sections and entity.get_logistic_sections()
        if sections and sections.valid then
          for _, section in ipairs(sections.sections or {}) do
            if section.valid and section.active then
              for _, filter in ipairs(section.filters or {}) do
                local val = filter.value
                if val and val.name and (val.type == nil or val.type == "item") and (filter.min or 0) > 0 then
                  local key = "item/" .. val.name
                  if relevant[key] then boundary_in[key] = true end
                end
              end
            end
          end
        end
      elseif mode == "active-provider" or mode == "passive-provider" then
        local inv = entity.get_inventory and entity.get_inventory(defines.inventory.chest)
        if inv then
          for _, stack in ipairs(inv.get_contents() or {}) do
            if (stack.count or 0) > 0 then
              local key = "item/" .. stack.name
              if relevant[key] then boundary_out[key] = true end
            end
          end
        end
      end
    end
  end

  -- 3. Pipes, underground pipes and pumps crossing the selection border.
  for _, entity in ipairs(surface.find_entities_filtered { area = area, type = FLUID_TYPES, force = force }) do
    if entity.valid then
      local fbn = entity.fluidbox_neighbours
      if fbn then
        local outside_conns = {}
        for _, group in ipairs(fbn) do
          for _, neighbour in ipairs(group or {}) do
            if neighbour and neighbour.valid and not inside(area, neighbour.position) then
              outside_conns[#outside_conns + 1] = neighbour
            end
          end
        end
        if #outside_conns > 0 then
          local contents = entity.get_fluid_contents and entity.get_fluid_contents() or {}
          for fluid, amount in pairs(contents) do
            local key = "fluid/" .. fluid
            if amount > 0 and relevant[key] then
              if entity.type == "pump" then
                local dx, dy = direction_vector(entity.direction)
                for _, conn in ipairs(outside_conns) do
                  local dot = (conn.position.x - entity.position.x) * dx + (conn.position.y - entity.position.y) * dy
                  if dot > 0 then boundary_out[key] = true
                  elseif dot < 0 then boundary_in[key] = true end
                end
              else
                pipe_boundary[key] = true
              end
            end
          end
        end
      end
    end
  end

  for key in pairs(pipe_boundary) do
    if not boundary_in[key] and not boundary_out[key] then
      local amount = net[key] or 0
      if amount < -EPSILON then boundary_in[key] = true
      elseif amount > EPSILON then boundary_out[key] = true end
    end
  end

  return boundary_in, boundary_out
end

-- Suggest default cell boundary ports from recipe topology plus physical boundary
-- evidence (belts, pipes, pumps and logistic chests). Internal intermediates
-- (both produced and consumed inside the cell) stay excluded by default so
-- ratio mismatches do not leak into inputs/outputs, unless they belong to a
-- terminal/source cycle (e.g. Kovarex) or physically cross the selection border.
function PortSuggestions.suggest(net, produced, consumed, rates, fuels, surface, area)
  local ports = { inputs = {}, outputs = {} }
  local materials, feeds = {}, {}
  for key in pairs(produced or {}) do
    if not (fuels and fuels[key]) then materials[key] = true end
  end
  for name, rate in pairs(rates or {}) do
    local recipe = storage.graph and storage.graph.recipes and storage.graph.recipes[name]
    if recipe then
      for _, product in ipairs(recipe.products) do
        local key = product.key
        if not (fuels and fuels[key]) and rate.normal * product.amount + rate.bonus * product.prod > EPSILON then
          for _, ingredient in ipairs(recipe.ingredients) do
            local input = ingredient.key
            if input ~= key and ingredient.amount > 0 and not (fuels and fuels[input]) then
              materials[input] = true
              feeds[input] = feeds[input] or {}
              feeds[input][#feeds[input] + 1] = key
            end
          end
        end
      end
    end
  end

  local keys = {}
  for key in pairs(materials) do keys[#keys + 1] = key end
  table.sort(keys)
  local component = Model._tarjan(keys, feeds)

  local has_upstream, has_downstream = {}, {}
  for _, key in ipairs(keys) do
    local from_id = component[key]
    for _, product in ipairs(feeds[key] or {}) do
      local to_id = component[product]
      if to_id and to_id ~= from_id then
        has_downstream[from_id] = true
        has_upstream[to_id] = true
      end
    end
  end

  local all_keys, intermediates = {}, {}
  for key in pairs(net or {}) do all_keys[key] = true end
  for key in pairs(produced or {}) do all_keys[key] = true end
  for key in pairs(consumed or {}) do all_keys[key] = true end
  for key in pairs(fuels or {}) do all_keys[key] = true end

  for key in pairs(all_keys) do
    local is_prod = (produced and produced[key] or 0) > EPSILON
    local is_cons = consumed and consumed[key] or false
    local is_fuel = fuels and fuels[key] ~= nil or false
    local amount = net and net[key] or 0

    if is_fuel then
      if amount < -EPSILON then ports.inputs[key] = true end
    elseif is_cons and not is_prod then
      ports.inputs[key] = true
    elseif is_prod and not is_cons then
      ports.outputs[key] = true
    elseif is_prod and is_cons then
      intermediates[key] = true
      local scc = component[key]
      if scc then
        if not has_downstream[scc] and amount > EPSILON then
          ports.outputs[key] = true
        elseif not has_upstream[scc] and amount < -EPSILON then
          ports.inputs[key] = true
        end
      end
    end
  end

  if next(intermediates) and surface and area then
    local boundary_in, boundary_out = scan_boundary(surface, area, intermediates, net or {})
    for key in pairs(intermediates) do
      local bin, bout = boundary_in[key], boundary_out[key]
      if bin and not bout then
        ports.inputs[key], ports.outputs[key] = true, nil
      elseif bout and not bin then
        ports.outputs[key], ports.inputs[key] = true, nil
      elseif bin and bout then
        local amount = net and net[key] or 0
        if amount < -EPSILON then
          ports.inputs[key], ports.outputs[key] = true, nil
        elseif amount > EPSILON then
          ports.outputs[key], ports.inputs[key] = true, nil
        end
      end
    end
  end

  return ports
end

return PortSuggestions
