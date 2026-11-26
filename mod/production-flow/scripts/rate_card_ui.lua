local Loc = require("scripts.locale")
local Balance = require("scripts.balance")
local BalanceUI = require("scripts.balance_ui")
local Capacity = require("scripts.cell_capacity")
local Cells = require("scripts.cells")
local Flow = require("scripts.cell_flow")
local History = require("scripts.history")
local HistoryUI = require("scripts.history_ui")
local Mining = require("scripts.mining_details")
local Model = require("scripts.model")
local RecipeDetails = require("scripts.recipe_details")
local Sampler = require("scripts.sampler")
local Surfaces = require("scripts.surfaces")

local R = {NAME = "ssk_rate_card"}
local PINNED = R.NAME .. "_pinned:"
local MIN_HISTORY_SECONDS = 600

local function pinned_name(tags)
  return PINNED .. tags.surface .. ":" .. (tags.cell or 0) .. ":" .. tags.key
end

local function is_pinned(card)
  return (card.name or ""):sub(1, #PINNED) == PINNED
end

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

function R.close_scoped(player, surface)
  local cards = player.gui.screen.children
  for i = #cards, 1, -1 do
    local card = cards[i]
    if (card.name == R.NAME or is_pinned(card)) and (not surface or card.tags.surface == surface) then
      card.destroy()
    end
  end
end

local function update_pin(button, pinned)
  button.toggled = pinned
  button.sprite = pinned and "utility/track_button" or "utility/track_button_white"
  button.tooltip = Loc(pinned and "rate-card-unpin" or "rate-card-pin")
end

local function update_fold(button, folded)
  button.sprite = folded and "utility/expand" or "utility/collapse"
  button.tooltip = Loc(folded and "rate-card-expand" or "rate-card-fold")
end

local function mining_columns(row, consuming)
  local drill_names = {}
  for name in pairs(row.drills or {}) do drill_names[#drill_names + 1] = name end
  table.sort(drill_names)
  local drills = {}
  for _, name in ipairs(drill_names) do
    drills[#drills + 1] = "[entity=" .. name .. "]×" .. row.drills[name]
  end
  local keys = {}
  for key in pairs(row.resource.products) do keys[#keys + 1] = key end
  table.sort(keys)
  local outputs, icons = {}, {}
  for _, key in ipairs(keys) do
    outputs[#outputs + 1] = RecipeDetails.material_label(key)
    icons[#icons + 1] = "[" .. key:gsub("/", "=", 1) .. "]"
  end
  local input = row.resource.input
  local from = input and RecipeDetails.material_label(input) or "—"
  local input_icon = input and ("[" .. input:gsub("/", "=", 1) .. "]") or "—"
  return #drills > 0 and Loc.join_list(drills, "\n") or "0",
    consuming and Loc.join_list(outputs, "\n") or from,
    input_icon .. " → " .. table.concat(icons, " + ")
end

local function recipe_table(body, rows, mines, width, consuming, recipe_icons, observed, surface)
  if #rows + #mines == 0 then return end
  body.add{type="label", style="caption_label", caption=Loc(consuming and "sankey-used-by" or "sankey-made-by")}
  local grid = body.add{type="table", name=consuming and "ssk_rate_card_used_by" or "ssk_rate_card_made_by", column_count=3}
  grid.style.horizontal_spacing, grid.style.vertical_spacing = 4, 4
  local machine_w, recipe_w = math.floor(width * 0.17), math.floor(width * 0.56)
  local item_w = width - machine_w - recipe_w - 8
  local function column(caption, column_width, style, tooltip)
    local label = grid.add{type="label", style=style, caption=caption, tooltip=tooltip}
    label.style.width, label.style.single_line = column_width, false
    label.style.horizontal_align = "right"
  end
  local function machines(types, recipe, resource)
    local names = {}
    for name in pairs(types or {}) do names[#names + 1] = name end
    if #names == 0 then return false end
    table.sort(names)
    local holder = grid.add{type="flow", direction="horizontal"}
    holder.style.width, holder.style.horizontal_align = machine_w, "right"
    local icons = holder.add{type="table", column_count=resource and 1 or math.max(1, math.floor(machine_w / 20))}
    icons.style.horizontal_spacing, icons.style.vertical_spacing = 0, 2
    for _, name in ipairs(names) do
      local prototype = prototypes.entity[name]
      local count = resource and types[name]
      local caption = "[entity=" .. name .. "]"
      if count then caption = caption .. "×" .. count end
      local link = icons.add{type="label", style="clickable_label", caption=caption,
        tooltip=Loc("rate-card-preview-machine", prototype and prototype.localised_name or name),
        tags={ssk_machine_status="card_preview", surface=surface, recipe=recipe, resource=resource,
          machine=name, count=count or nil}}
      link.style.width, link.style.horizontal_align, link.style.single_line = resource and machine_w or 20, "right", true
    end
    return true
  end
  column(Loc("rate-card-machine"), machine_w, "grey_label")
  column(Loc(consuming and "rate-card-recipe-to" or "rate-card-recipe-from"), item_w, "grey_label")
  column(Loc("machine-status-recipe"), recipe_w, "grey_label")
  local limit = consuming and #rows or math.min(#rows, RecipeDetails.MATERIAL_PREVIEW_LIMIT)
  for i = 1, limit do
    local row = rows[i]
    local items, recipe = RecipeDetails.material_columns(row, consuming, BalanceUI.format_rate)
    local observation = observed and observed[row.name]
    if not machines(observation and observation.entities, row.name) then
      local icons = recipe_icons and recipe_icons("recipe/" .. row.name)
      column(icons or "—", machine_w, nil, icons and recipe or Loc("machine-status-no-machines-observed"))
    end
    column(items, item_w, nil, recipe)
    column(recipe, recipe_w, nil, recipe)
  end
  for _, mine in ipairs(mines) do
    local drill_counts, items, resource = mining_columns(mine, consuming)
    if not machines(surface and mine.drills, nil, mine.resource.name) then
      column(drill_counts, machine_w, nil, Loc("rate-card-mining-drill-count"))
    end
    local item_tip = not consuming and mine.resource.input and Loc("rate-card-mining-required-fluid", items)
    column(items, item_w, nil, item_tip or nil)
    column(resource, recipe_w, nil, Loc("rate-card-mining-resource", mine.resource.caption))
  end
  if #rows > limit then
    body.add{type="label", style="grey_label", caption=Loc("recipe-details-more", string.format("%d", #rows - limit))}
  end
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
  local recipe_context = {rates = rates}
  local mined, mining_uses = {}, {}
  if not cell then mined, mining_uses = Mining.sources_and_uses(sidx, key) end
  if options.recipe_tables or #mined + #mining_uses > 0 then
    local made_by = RecipeDetails.material_rows(recipe_context, key, false)
    local used_by = RecipeDetails.material_rows(recipe_context, key, true)
    if #made_by + #used_by + #mined + #mining_uses > 0 then
      body.add{type="line"}
      if recipe_caption and #made_by + #used_by > 0 then
        body.add{type="label", caption=recipe_caption, style="grey_label"}
      end
      local observed = options.player and not cell and Sampler.machine_status(sidx, options.player.force_index)
      local preview_surface = options.player and sidx
      recipe_table(body, made_by, mined, width, false, options.recipe_icons, observed, preview_surface)
      recipe_table(body, used_by, mining_uses, width, true, options.recipe_icons, observed, preview_surface)
    end
    return
  end
  local recipes = RecipeDetails.material(recipe_context, key, BalanceUI.format_rate, nil, options.recipe_icons)
  if recipes then
    body.add{type = "line"}
    if recipe_caption then body.add{type = "label", caption = recipe_caption, style = "grey_label"} end
    local label = body.add{type = "label", caption = recipes}
    label.style.single_line = false
    label.style.width = width
  end
end

local function refresh_card(player, card, us, bring_forward, models)
  local tags = card.tags
  local cell = tags.cell and Flow.records()[tags.cell]
  local pinned = is_pinned(card)
  if not game.surfaces[tags.surface] or not material(tags.key) or tags.force and tags.force ~= player.force_index
    or tags.cell and (not cell or cell.surface_index ~= tags.surface)
    or not pinned and (not us or us.sidx ~= tags.surface
      or tags.cell and (us.tab_id ~= "cells" or not us.cells or us.cells.selected ~= tags.cell)
      or not tags.cell and us.tab_id == "cells") then
    card.destroy()
    return
  end
  if bring_forward then card.bring_to_front() end
  local capacity = pinned and tags.capacity or not pinned and cell and us.cells.mode == "capacity"
  local period = (pinned and tags.period or us and us.period) or Sampler.DEFAULT_PERIOD
  local width, _, screen_h = dimensions(player)
  if tags.folded then
    card.style.width = width
    return
  end
  local scroll = card.ssk_rate_card_scroll
  local style = scroll.style.name
  if style and style ~= "ssk_rate_card_scroll" then
    scroll.style = "ssk_rate_card_scroll"
    scroll.vertical_scroll_policy = "auto-and-reserve-space"
    tags.tick = nil
  end
  local tick = math.floor(game.tick / 300)
  if tags.tick == tick and tags.period == period and tags.capacity == capacity and tags.width == width
    and tags.screen_h == screen_h then return end
  tags.tick, tags.period, tags.capacity, tags.width, tags.screen_h = tick, period, capacity, width, screen_h
  card.tags = tags
  card.style.width = width
  scroll.style.horizontally_stretchable = true
  local location = card.location
  local top = location and (location.y or location[2]) or 0
  scroll.style.maximal_height = math.max(140, screen_h - math.floor(top / player.display_scale) - 59)
  local context
  if not cell then
    local scope = tags.surface .. ":" .. period
    context = models[scope]
    if not context then
      local model = Model.build(tags.surface, period)
      context = {model=model, read_balance=Balance.material_reader(tags.surface, model, true)}
      models[scope] = context
    end
  end
  R.render_body(scroll.ssk_rate_card_body, tags.surface, tags.key, period, width - 48,
    {cell=cell, capacity=capacity, model=context and context.model, read_balance=context and context.read_balance,
      recipe_tables=true, player=player})
end

function R.refresh(player, us, bring_forward)
  local models = {}
  local cards = player.gui.screen.children
  for i = #cards, 1, -1 do
    local card = cards[i]
    if card.name == R.NAME or is_pinned(card) then refresh_card(player, card, us, bring_forward, models) end
  end
end

function R.on_click(player, element, us)
  local action = element.tags.ssk_rate_card
  if not action then return false end
  local card = element.parent.parent
  if action == "close" then
    card.destroy()
  elseif action == "fold" then
    local tags = card.tags
    tags.folded = not tags.folded
    if not tags.folded then tags.tick = nil end
    card.tags = tags
    card.ssk_rate_card_scroll.visible = not tags.folded
    update_fold(element, tags.folded)
    if not tags.folded then refresh_card(player, card, us, false, {}) end
  elseif action == "pin" then
    if is_pinned(card) then
      R.close(player)
      card.name = R.NAME
      update_pin(element, false)
    else
      card.name = pinned_name(card.tags)
      update_pin(element, true)
    end
  else
    return false
  end
  return true
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
  local screen = player.gui.screen
  local tags = {key=key, surface=surface, cell=cell, force=player.force_index}
  local pinned = screen[pinned_name(tags)]
  if pinned then
    pinned.bring_to_front()
    return true
  end
  local previous = screen[R.NAME]
  if previous and previous.tags.key == key and previous.tags.surface == surface and previous.tags.cell == cell then
    return R.close(player)
  end
  R.close(player)
  local width, screen_w, screen_h = dimensions(player)
  local occupied = {}
  for _, other in ipairs(screen.children) do
    if is_pinned(other) and other.tags.slot then occupied[other.tags.slot] = true end
  end
  local slot = 0
  while occupied[slot] do slot = slot + 1 end
  tags.slot = slot
  local card = screen.add{type = "frame", name = R.NAME, direction = "vertical", tags=tags}
  local scale = player.display_scale
  local columns = math.max(1, math.floor((screen_w - 48) / (width + 12)))
  local row = math.floor(slot / columns) % math.max(1, math.floor((screen_h - 160) / 28))
  local x = screen_w - width - 36 - (slot % columns) * (width + 12) - row * 12
  card.location = {math.floor(math.max(12, x) * scale), math.floor((96 + row * 28) * scale)}
  local header = card.add{type = "flow", style = "frame_header_flow", direction = "horizontal"}
  header.drag_target = card
  local title = header.add{type = "label", style = "frame_title",
    caption = Loc.join("[", key:gsub("/", "=", 1), "] ", prototype.localised_name or key)}
  title.style.maximal_width, title.style.single_line = width - 108, true
  title.tooltip = prototype.localised_name or key
  title.ignored_by_interaction = true
  local stretch = header.add{type = "empty-widget", style = "draggable_space_header"}
  stretch.style.horizontally_stretchable = true
  stretch.style.height = 24
  stretch.drag_target = card
  local fold = header.add{type="sprite-button", name="ssk_rate_card_fold", style="frame_action_button",
    sprite="utility/collapse", tags={ssk_rate_card="fold"}}
  update_fold(fold, false)
  local pin = header.add{type="sprite-button", name="ssk_rate_card_pin", style="frame_action_button",
    sprite="utility/track_button_white", hovered_sprite="utility/track_button",
    clicked_sprite="utility/track_button", tags={ssk_rate_card="pin"}}
  update_pin(pin, false)
  header.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip=Loc("rate-card-close"), tags = {ssk_rate_card = "close"}}
  local scroll = card.add{type="scroll-pane", name="ssk_rate_card_scroll", style="ssk_rate_card_scroll",
    horizontal_scroll_policy="never", vertical_scroll_policy="auto-and-reserve-space"}
  scroll.add{type="flow", name="ssk_rate_card_body", direction="vertical"}.style.vertical_spacing = 5
  refresh_card(player, card, us, false, {})
  card.bring_to_front()
  return true
end

return R
