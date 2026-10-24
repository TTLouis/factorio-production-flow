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
for _, renderer in ipairs({ "sprites", "poly" }) do
  local us = { view = "detail", layout = "clean", renderer = renderer, lines = "curves", heights = "sqrt",
    period = 0, preset = "all", canvas_w = 1000 }
  SK.fill(player, c, us, 1000, 700, true)
  local elements = collect(c)
  assert(us.show_labels == false and #elements.toggles == 1, "hover-only default and toolbar toggle")
  local before = route(storage.sk_render[1])
  local key = "item/electronic-circuit"
  assert(elements.icons[key] and elements.bars[key], "fixture needs icon and bar targets")
  for k, label in pairs(elements.labels) do
    assert(label.visible == false, "unselected header must be hidden")
    local icon, bar = elements.icons[k], elements.bars[k]
    assert(icon.raise_hover_events and bar.raise_hover_events, "both hit areas must highlight")
    assert(type(icon.tooltip) == "table" and icon.tooltip == bar.tooltip, "one native hover card on either target")
    assert(#icon.tooltip == 6 and icon.tooltip[5] == "\n", "compact name and rate on separate lines")
    if renderer == "poly" then assert(bar.sprite == "ssk-node-hit", "polygon hit area must be transparent") end
  end
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
  SK.on_hover(event(elements.icons["item/plastic-bar"]), true)
  SK.on_hover(event(elements.icons["item/plastic-bar"]), false)
  assert(storage.sk_render[1].selected == key and elements.labels[key].visible)
  assert(before == route(storage.sk_render[1]), "pinning changed routes")
  -- Live redraw retains pinned state and updates native tooltip data.
  SK.fill(player, c, us, 1000, 700, false)
  elements = collect(c)
  assert(elements.labels[key].visible and elements.bars[key].tooltip[6]:find("items/s", 1, true))
  assert(SK.on_click(event(elements.icons[key]), us) == "rebuild" and not us.sel)
  SK.fill(player, c, us, 1000, 700, false)
  assert(not collect(c).labels[key].visible, "second click must unpin")
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
c.destroy()
TREQ("scripts.canvas").clear(player.index)
print("HOVER LABEL TESTS OK")
