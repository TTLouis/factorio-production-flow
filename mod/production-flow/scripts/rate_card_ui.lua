local Loc = require("scripts.locale")
local Balance = require("scripts.balance")
local BalanceUI = require("scripts.balance_ui")
local Capacity = require("scripts.cell_capacity")
local Cells = require("scripts.cells")
local Flow = require("scripts.cell_flow")
local History = require("scripts.history")
local HistoryUI = require("scripts.history_ui")
local Model = require("scripts.model")
local RecipeDetails = require("scripts.recipe_details")
local Sampler = require("scripts.sampler")
local Surfaces = require("scripts.surfaces")

local R = {NAME = "ssk_rate_card"}
local MIN_HISTORY_SECONDS = 600

local function cell_totals(cell, key, period, capacity)
  local rates, fuels
  if capacity then
    rates, fuels = Capacity.rates(Cells.members(cell), nil, cell.ports and cell.ports.inputs, true)
  else
    rates = Flow.measured_rates(cell, period)
  end
  local made, used = 0, 0
  Capacity.flows(rates, function(_, material, rate)
    if material == key then used = used + rate end
  end, function(_, material, rate)
    if material == key then made = made + rate end
  end)
  for _, rate in pairs(fuels and fuels[key] or {}) do used = used + rate end
  return made, used, rates
end

local function material(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  if kind == "item" or kind == "fluid" then return prototypes[kind][name], kind end
end

local function dimensions(player)
  local scale, resolution = player.display_scale, player.display_resolution
  local screen_w, screen_h = math.floor(resolution.width / scale), math.floor(resolution.height / scale)
  return math.min(430, screen_w - 32), screen_w, screen_h
end

function R.close(player)
  local card = player.gui.screen[R.NAME]
  if not card then return false end
  card.destroy()
  return true
end

function R.render_body(body, sidx, key, period, width, options)
  local cell, capacity = options.cell, options.capacity
  body.clear()
  body.style.width = width
  local made, used, rates, row
  if cell then
    made, used, rates = cell_totals(cell, key, period, capacity)
  else
    local model = options.model or Model.build(sidx, period)
    local read = options.read_balance or Balance.material_reader(sidx, model, true)
    row = read(key)
    made, used = row.prod, row.cons
    rates = options.recipe_rates or RecipeDetails.from_model(model.rates.recipes)
  end
  local _, kind = material(key)
  local units = Loc(kind == "fluid" and "unit-fluid-rate" or "history-items-s")
  local surface = game.surfaces[sidx]
  local scope = cell and Loc.join(Surfaces.rich(surface), " · ", cell.name) or Surfaces.rich(surface)
  local rate_seconds = period > 0 and period or settings.global["ssk-window-seconds"].value
  local history_seconds = math.min(Sampler.PERIODS[#Sampler.PERIODS], math.max(MIN_HISTORY_SECONDS, rate_seconds * 2))
  local period_caption = Sampler.duration(rate_seconds)
  local context = body.add{type = "label", style = "grey_label", caption = Loc.join(scope, " · ",
    capacity and Loc("cells-mode-capacity") or period_caption)}
  context.style.single_line, context.style.maximal_width = false, width
  BalanceUI.card_totals(body, made, used, row)
  local history = History.card_rates(sidx, history_seconds, key, cell)
  body.add{type = "line"}
  body.add{type = "label", name = "ssk_rate_card_history", style = "caption_label",
    caption = Loc("rate-card-history", Sampler.duration(history_seconds))}
  if history.seconds > 0 then
    HistoryUI.draw_card_rates(body, history, width, units, options.plot_height)
  else
    local caption = body.add{type = "label", style = "grey_label", caption = Loc("rate-card-no-samples")}
    caption.style.single_line = false
  end
  local recipe_caption
  if not capacity and rate_seconds < history_seconds and (made == 0 or used == 0) then
    rates = cell and Flow.measured_rates(cell, history_seconds)
      or RecipeDetails.from_model(Sampler.rates(sidx, history_seconds).recipes)
    recipe_caption = Loc("rate-card-recent-recipes", Sampler.duration(history_seconds))
  end
  local recipes = RecipeDetails.material({rates = rates}, key, BalanceUI.format_rate, nil, options.recipe_icons)
  if recipes then
    body.add{type = "line"}
    if recipe_caption then body.add{type = "label", caption = recipe_caption, style = "grey_label"} end
    local label = body.add{type = "label", caption = recipes}
    label.style.single_line = false
    label.style.width = width
  end
end

function R.refresh(player, us, bring_forward)
  local card = player.gui.screen[R.NAME]
  if not card then return end
  local tags = card.tags
  local cell = tags.cell and Flow.records()[tags.cell]
  if us.tab_id == "sankey" or us.sidx ~= tags.surface or not material(tags.key)
    or (tags.cell and (not cell or cell.surface_index ~= tags.surface or us.tab_id ~= "cells"
      or not us.cells or us.cells.selected ~= tags.cell))
    or (not tags.cell and us.tab_id == "cells") then
    R.close(player)
    return
  end
  if bring_forward then card.bring_to_front() end
  local capacity = cell and us.cells.mode == "capacity"
  local period = us.period or Sampler.DEFAULT_PERIOD
  local width, _, screen_h = dimensions(player)
  local tick = math.floor(game.tick / 300)
  if tags.tick == tick and tags.period == period and tags.capacity == capacity and tags.width == width
    and tags.screen_h == screen_h then return end
  tags.tick, tags.period, tags.capacity, tags.width, tags.screen_h = tick, period, capacity, width, screen_h
  card.tags = tags
  card.style.width = width
  local scroll = card.ssk_rate_card_scroll
  scroll.style.maximal_height = math.max(140, screen_h - 155)
  R.render_body(scroll.ssk_rate_card_body, tags.surface, tags.key, period, width - 48, {cell=cell, capacity=capacity})
end

function R.toggle(player, us, key)
  local prototype = type(key) == "string" and material(key)
  local surface = us.sidx
  if not prototype or not surface then return false end
  local cell
  if us.tab_id == "cells" then
    cell = us.cells and us.cells.selected
    local record = cell and Flow.records()[cell]
    if not record or record.surface_index ~= surface or #Flow.ids(surface, cell) > 0 then return false end
  end
  local previous = player.gui.screen[R.NAME]
  if previous and previous.tags.key == key and previous.tags.surface == surface and previous.tags.cell == cell then
    return R.close(player)
  end
  R.close(player)
  local width, screen_w = dimensions(player)
  local card = player.gui.screen.add{type = "frame", name = R.NAME, direction = "vertical",
    tags = {key = key, surface = surface, cell = cell}}
  local scale = player.display_scale
  card.location = {math.floor(math.max(12, screen_w - width - 36) * scale), math.floor(96 * scale)}
  local header = card.add{type = "flow", style = "frame_header_flow", direction = "horizontal"}
  header.drag_target = card
  local title = header.add{type = "label", style = "frame_title",
    caption = Loc.join("[", key:gsub("/", "=", 1), "] ", prototype.localised_name or key)}
  title.style.maximal_width, title.style.single_line = width - 56, true
  title.tooltip = prototype.localised_name or key
  title.ignored_by_interaction = true
  local stretch = header.add{type = "empty-widget", style = "draggable_space_header"}
  stretch.style.horizontally_stretchable = true
  stretch.style.height = 24
  stretch.drag_target = card
  header.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tags = {ssk_ui = "rate_card_close"}}
  local scroll = card.add{type = "scroll-pane", name = "ssk_rate_card_scroll", horizontal_scroll_policy = "never"}
  local body = scroll.add{type = "flow", name = "ssk_rate_card_body", direction = "vertical"}
  body.style.vertical_spacing = 5
  R.refresh(player, us)
  card.bring_to_front()
  return true
end

return R
