-- Interaction contracts: hidden labels retain layout; icons and bars behave alike.
local SK = TREQ("scripts.sankey_ui")
local player = game.players[1]
local c = player.gui.screen.add { type = "flow", name = "ssk_hover_test", direction = "vertical" }
local function collect(el, result)
  result = result or { icons = {}, bars = {}, labels = {}, toggles = {} }
  if el.tags.ssk_label then result.labels[el.tags.ssk_label] = el end
  if el.tags.ssk_sk == "node" then
    local bucket = el.tags.part == "bar" and result.bars or result.icons
    bucket[el.tags.key] = el
  end
  if el.tags.ssk_sk == "show_labels" then result.toggles[#result.toggles + 1] = el end
  for _, child in ipairs(el.children) do collect(child, result) end
  return result
end
local function route(st)
  local parts = {}
  for _, p in ipairs(st.paths) do
    for _, s in ipairs(p.pieces) do
      parts[#parts + 1] = table.concat({p.from, p.to, s.kind, s.x, s.y, s.w, s.h}, ",")
    end
  end
  return table.concat(parts, "|")
end
local function event(el) return { player_index = 1, element = el } end
local BalanceUI = TREQ("scripts.balance_ui")
local rate_units = TREQ("scripts.locale")("history-items-s")
local positive = LOC(BalanceUI.hover_details(3, 1, rate_units))
local negative = LOC(BalanceUI.hover_details(1, 3, rate_units))
local neutral = LOC(BalanceUI.hover_details(3, 3, rate_units))
assert(positive:find("[color=0.5,0.9,0.5]+2.00[/color]", 1, true), "positive net should be green")
assert(negative:find("[color=1,0.45,0.4]−2.00[/color]", 1, true), "negative net should be red")
assert(neutral:find("Net /s  0", 1, true) and not neutral:find("[color=", 1, true), "zero net should be neutral")
local function check_balance(elements, key)
  local icon, bar = elements.icons[key], elements.bars[key]
  assert(icon and bar and icon.tooltip == bar.tooltip, "material hover must match its icon")
  local hover = LOC(bar.tooltip)
  assert(bar.tags.ssk_card_material == key and icon.tags.ssk_card_material == key, "bars and icons should pin the same material")
  for _, field in ipairs({ "Produced", "consumed", "Net /s", "Producers", "Consumers", "Stock", "Empty in" }) do
    assert(hover:find(field, 1, true), "material hover is missing " .. field)
  end
end
for _, renderer in ipairs({ "sprites", "poly" }) do
  local us = { view = "detail", layout = "clean", renderer = renderer, lines = "curves", heights = "sqrt",
    period = 0, preset = "all", canvas_w = 1000 }
  SK.fill(player, c, us, 1000, 700, true)
  local elements = collect(c)
  assert(us.show_labels == false and #elements.toggles == 1, "hover-only default and toolbar toggle")
  local before = route(storage.sk_render[1])
  local key = "item/electronic-circuit"
  assert(elements.icons[key] and elements.bars[key], "fixture needs icon and bar targets")
  check_balance(elements, key)
  local fluid_hover = LOC(elements.bars["fluid/petroleum-gas"].tooltip)
  assert(fluid_hover:find("Net /s", 1, true) and not fluid_hover:find("Stock", 1, true),
    "fluid hovers show flow details without chest stock")
  for k, label in pairs(elements.labels) do
    assert(label.visible == false, "unselected header must be hidden")
    local icon, bar = elements.icons[k], elements.bars[k]
    assert(icon.raise_hover_events and bar.raise_hover_events, "both hit areas must highlight")
    assert(type(icon.tooltip) == "table" and icon.tooltip == bar.tooltip, "one native hover card on either target")
    -- Name and rate first; then a lab estimate for science packs and the recipe details.
    local tail = #icon.tooltip
    if tail >= 8 and icon.tooltip[tail - 1] == "\n\n" then
      local text = LOC(icon.tooltip[tail])
      assert(text:find("Made by:", 1, true) or text:find("Used by:", 1, true) or text:find("Recipe (", 1, true),
        "recipe details close the hover card: " .. text)
      tail = tail - 2
    end
    assert(icon.tooltip[5] == "\n" and type(icon.tooltip[6]) == "table",
      "compact name and rate stay on separate lines before recipe breakdown")
    if renderer == "poly" then assert(bar.sprite == "ssk-node-hit", "polygon hit area must be transparent") end
  end
  -- Recipe bars show the recipe, its measured rates and the machines running it.
  local oil = assert(elements.bars["recipe/advanced-oil-processing"], "fixture needs a recipe bar")
  local recipe_text = LOC(oil.tooltip[#oil.tooltip])
  assert(recipe_text:find("Recipe (", 1, true) and recipe_text:find("[fluid=crude-oil]", 1, true)
    and recipe_text:find("→", 1, true), "recipe bar lists the recipe per craft: " .. recipe_text)
  local made = LOC(elements.bars[key].tooltip[#elements.bars[key].tooltip])
  assert(made:find("Made by:", 1, true) and made:find("[recipe=electronic-circuit]", 1, true)
    and made:find("[item=iron-plate]", 1, true), "material bar lists the recipes making it: " .. made)
  local _, made_sections = LOC(elements.bars[key].tooltip):gsub("Made by", "")
  local _, used_sections = LOC(elements.bars[key].tooltip):gsub("Used by", "")
  assert(made_sections == 1 and used_sections == 1, "hover should contain one recipe breakdown")
  if renderer == "sprites" then print("RECIPE DETAILS SAMPLE:\n" .. recipe_text .. "\n--\n" .. made) end
  -- Hover does not rebuild the chart or change selection/positions.
  local icon, bar = elements.icons[key], elements.bars[key]
  assert(SK.on_hover(event(bar), true))
  assert(SK.on_hover(event(bar), false))
  assert(us.sel == nil and before == route(storage.sk_render[1]), "hover moved layout or selection")
  -- Clicking a bar pins its label; another hover restores the pinned chain on exit.
  assert(SK.on_click(event(bar), us) == "rebuild" and us.sel == key)
  SK.fill(player, c, us, 1000, 700, false)
  elements = collect(c)
  assert(elements.labels[key].visible, "selected label must stay visible")
  assert(not elements.labels["item/plastic-bar"].visible, "unselected label leaked")
  local unrelated = "item/plastic-bar"
  assert(elements.icons[unrelated].style.draw_grayscale_picture == true,
    "Full Sankey must gray unrelated icons without disabling their click targets")
  assert(elements.icons[unrelated].enabled ~= false and not elements.icons[key].style.draw_grayscale_picture
    and not elements.icons["item/iron-plate"].style.draw_grayscale_picture,
    "Selected and upstream nodes must retain their normal icons")
  local visual = storage.sk_render[1].node_visuals[unrelated]
  assert(visual.dimmed and elements.labels[unrelated].style.font_color[1] == .4)
  if renderer == "sprites" then
    assert(elements.bars[unrelated].sprite == TREQ("shared.sprites").bar(TREQ("shared.palette").DIM),
      "Unrelated sprite bars must dim with their icons")
  else
    assert(visual.shapes[#visual.shapes].object.color.a == .16,
      "Unrelated polygon bars must dim with their icons")
  end
  SK.on_hover(event(elements.icons["item/plastic-bar"]), true)
  assert(not elements.icons[unrelated].style.draw_grayscale_picture and elements.icons[key].style.draw_grayscale_picture,
    "Hover must temporarily trace the hovered chain")
  SK.on_hover(event(elements.icons["item/plastic-bar"]), false)
  assert(elements.icons[unrelated].style.draw_grayscale_picture and not elements.icons[key].style.draw_grayscale_picture,
    "Leaving hover must restore the pinned chain")
  assert(storage.sk_render[1].selected == key and elements.labels[key].visible)
  assert(before == route(storage.sk_render[1]), "pinning changed routes")
  -- Live redraw retains pinned state and updates native tooltip data.
  SK.fill(player, c, us, 1000, 700, false)
  elements = collect(c)
  assert(elements.labels[key].visible and LOC(elements.bars[key].tooltip[6]):find("items/s", 1, true))
  assert(SK.on_click(event(elements.icons[key]), us) == "rebuild" and not us.sel)
  SK.fill(player, c, us, 1000, 700, false)
  assert(not collect(c).labels[key].visible, "second click must unpin")
  assert(not collect(c).icons[unrelated].style.draw_grayscale_picture,
    "Clearing the selected node must restore unrelated icons")
  for _, enabled in ipairs({ true, false }) do
    local toggle = collect(c).toggles[1]; toggle.state = enabled
    assert(SK.on_checked(event(toggle), us) == "rebuild")
    SK.fill(player, c, us, 1000, 700, false)
    for _, label in pairs(collect(c).labels) do assert(label.visible == enabled, "Show labels toggle") end
    assert(before == route(storage.sk_render[1]), "toggle must not reflow graph")
  end
  -- Focus/Balance keep the centre label and retain click-to-recentre navigation.
  for _, neighborhood in ipairs({ false, true }) do
    local fx = { view = "focus", focus = key, focus_steps = 2, neighborhood = neighborhood,
      renderer = renderer, heights = "sqrt", lines = "curves", period = 0, canvas_w = 520 }
    SK.fill(player, c, fx, 520, 600, true)
    elements = collect(c)
    assert(#elements.toggles == 1 and elements.labels[key].visible, "focused item must be identified")
    check_balance(elements, key)
    for _,target in pairs(elements.icons) do assert(not target.style.draw_grayscale_picture,
      "Full Sankey node dimming must not affect Focus/Balance icons") end
    local other
    for k, target in pairs(elements.bars) do
      if k ~= key and k:sub(1, 5) == "item/" then other = target; break end
    end
    assert(other, "focus fixture has no neighbour")
    assert(SK.on_click(event(other), fx) == "rebuild" and fx.focus == other.tags.key:gsub("#.*$", ""))
    SK.fill(player, c, fx, 520, 600, false)
    assert(collect(c).labels[fx.focus].visible)
    assert(storage.sk_render["1:focus"].selected == (not neighborhood and fx.focus or nil))
  end
end
-- Full prototype names survive in the native tooltip as LocalisedStrings.
local key = "electronic-circuit"
local previous = rawget(prototypes.item, key)
prototypes.item[key] = { name = key, localised_name = { "item-name.electronic-circuit" },
  subgroup = { name = "x" }, group = { name = "g" } }
SK.fill(player, c, { view = "detail", layout = "clean", period = 0, canvas_w = 1000 }, 1000, 700, true)
assert(collect(c).icons["item/" .. key].tooltip[4][1] == "item-name.electronic-circuit", "localised name lost")
prototypes.item[key] = previous

local RateCard = TREQ("scripts.rate_card_ui")
local state = {sidx = player.surface.index, tab_id = "focus", period = 60}
assert(RateCard.toggle(player, state, "item/" .. key))
local pinned = player.gui.screen[RateCard.NAME]
local body = pinned.ssk_rate_card_scroll.ssk_rate_card_body
assert(body.ssk_card_rates_plot and body.ssk_card_net_plot, "pinned card should draw both history plots")
RateCard.refresh(player, state)
assert(player.gui.screen[RateCard.NAME] == pinned, "refresh should keep the pinned frame")
assert(RateCard.toggle(player, state, "item/" .. key) and not player.gui.screen[RateCard.NAME], "pin should toggle")
assert(RateCard.toggle(player, state, "item/" .. key))
RateCard.refresh(player, {sidx = state.sidx + 1, tab_id = "focus"})
assert(not player.gui.screen[RateCard.NAME], "surface changes must close a card from the old scope")
assert(RateCard.toggle(player, state, "item/" .. key))
RateCard.refresh(player, {sidx = state.sidx, tab_id = "sankey"})
assert(not player.gui.screen[RateCard.NAME], "Full Sankey uses a docked card instead of the floating window")
local original_scale = player.display_scale
player.display_scale = 1.5
assert(RateCard.toggle(player, state, "item/" .. key))
local card = player.gui.screen[RateCard.NAME]
local screen_w = math.floor(player.display_resolution.width / player.display_scale)
assert(card.location[1] == math.floor(math.max(12, screen_w - math.min(430, screen_w - 32) - 36) * 1.5),
  "Floating card location must be in screen pixels")
RateCard.close(player)
player.display_scale = original_scale

local Sampler = TREQ("scripts.sampler")
local original_cell_rates = Sampler.cell_rates
Sampler.cell_rates = function() return { ["removed-cell-recipe"] = {cps=1, normal_cps=1} } end
local cell_body = c.add{type="flow", direction="vertical"}
RateCard.render_body(cell_body, state.sidx, "item/" .. key, state.period, 300,
  {cell={id=987654, surface_index=state.sidx, since=0, name="Test cell"}})
Sampler.cell_rates = original_cell_rates
local totals = cell_body.children[2]
assert(totals.type == "table" and LOC(totals.children[2].caption) == "0.000",
  "Removed recipes must not contribute to current cell totals")

local Balance, Model = TREQ("scripts.balance"), TREQ("scripts.model")
local model = Model.build(state.sidx, state.period)
local stats_only = "item/stats-only-fixture"
model.rates.nodes[stats_only] = {prod=7, cons=3}
local read = Balance.material_reader(state.sidx, model, true)
local browse = Balance.material_reader(state.sidx, model)
local row = assert(read(stats_only))
assert(row.prod==7 and row.cons==3 and not browse(stats_only),
  "Stats-only materials have measured totals in cards without changing Balance list membership")
model.rates.nodes[stats_only] = nil
c.destroy()
TREQ("scripts.canvas").clear(player.index)
print("HOVER LABEL TESTS OK")
