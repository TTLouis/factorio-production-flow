local C = TREQ("scripts.chest_stock")
local Cannons = TREQ("scripts.se_cannons")
local Gr = TREQ("scripts.groups")
local Panels = TREQ("scripts.se_transfer_panels")
local Endpoints = TREQ("scripts.transfer_endpoints")
local Cells = TREQ("scripts.cells")
local Rail = TREQ("scripts.cell_rail")
local Flow = TREQ("scripts.cell_flow")
local CellsUI = TREQ("scripts.cells_ui")
local Outlines = TREQ("scripts.cell_outlines")
local Sampler = TREQ("scripts.sampler")
local Transfers = TREQ("scripts.transfers")
local TransfersUI = TREQ("scripts.transfers_ui")
local Model = TREQ("scripts.model")
local View = TREQ("scripts.view")
local Neighborhood = TREQ("scripts.neighborhood")

local player = game.players[1]

-- 1. ChestStock: sorted multi-surface 1/tick discovery, mid-discovery surface delete, single-surface fast path
do
  local saved_cs, saved_stock, saved_surfaces = storage.chest_stock, storage.stock, game.surfaces
  local saved_per = C.PER_TICK
  local discovered, reads = {}, 0
  local function mk_surface(idx, with_valid)
    local s = { index = idx, name = "surf-" .. idx }
    if with_valid then s.valid = true end
    s.find_entities_filtered = function(filter)
      if filter.type == "cargo-pod" then discovered[#discovered + 1] = idx end
      return {}
    end
    return s
  end
  local s1, s2, s3 = mk_surface(1, false), mk_surface(2, true), mk_surface(3, true)
  game.surfaces = { [3] = s3, [1] = s1, [2] = s2 }
  storage.stock, storage.chest_stock, storage.stock_basis = {}, nil, "physical-storage-v2"
  C.init()
  local c1 = {
    valid = true, type = "container", unit_number = 90001, surface = s1, surface_index = 1, force = game.forces.player,
    get_inventory = function()
      return { valid = true, get_contents = function() reads = reads + 1; return { { name = "iron-plate", count = 15 } } end }
    end,
  }
  C.add(c1)
  C.request(100)
  local b = storage.chest_stock.batch
  assert(b and b.discover and b.discover[1] == 1 and b.discover[2] == 2 and b.discover[3] == 3,
    "Multi-surface discovery must sort surface indices deterministically")
  C.tick(100)
  assert(#discovered == 1 and discovered[1] == 1 and reads == 0,
    "Multi-surface scan must discover 1 surface before reading chests")
  assert(b.dcursor == 2)
  C.on_surface_deleted(2)
  assert(#b.discover == 2 and b.discover[1] == 1 and b.discover[2] == 3 and b.dcursor == 2,
    "Deleting an undiscovered surface mid-scan must compact discover cleanly")
  C.tick(101)
  assert(#discovered == 2 and discovered[2] == 3 and b.discover == nil and reads == 0,
    "Final multi-surface discovery tick must not start chest reads on the same tick")
  C.tick(102)
  assert(reads == 1 and #storage.stock == 1 and storage.stock[1].tick == 102 and storage.stock[1].s[1]["item/iron-plate"] == 15,
    "Chest scan completes after multi-surface discovery finishes")

  -- Single-surface fast path (valid=nil just like mock2)
  discovered, reads = {}, 0
  game.surfaces = { [1] = s1 }
  storage.chest_stock.next_tick = 0
  C.tick(200)
  assert(#discovered == 1 and discovered[1] == 1 and reads == 1 and #storage.stock == 2 and storage.stock[2].tick == 200,
    "Single-surface scan must discover and read chests in the same tick")

  C.PER_TICK = saved_per
  storage.chest_stock, storage.stock, game.surfaces = saved_cs, saved_stock, saved_surfaces
end

-- 2. se_cannons: persistent storage zone_cache, legacy in_flight migration + min_eta settling, C.query early break
do
  local saved_mods, saved_cannons, saved_remote = script.active_mods, storage.se_cannons, remote
  local saved_surfaces, saved_recipes = game.surfaces, prototypes.recipe
  local saved_effect, saved_tick, saved_asm_out = defines.events.on_script_trigger_effect, game.tick, defines.inventory.assembling_machine_output
  script.active_mods = { ["space-exploration"] = "0.7.64" }
  defines.events.on_script_trigger_effect = 99
  defines.inventory.assembling_machine_output = defines.inventory.assembling_machine_output or 3
  prototypes.recipe = setmetatable({
    ["se-delivery-cannon-pack-iron-plate"] = {
      ingredients = { { type = "item", name = "iron-plate", amount = 100 }, { type = "item", name = "se-delivery-cannon-capsule", amount = 1 } },
      products = { { name = "se-delivery-cannon-package-iron-plate" } },
    },
  }, { __index = saved_recipes })

  local zone_calls = 0
  remote = {
    interfaces = { ["space-exploration"] = { get_zone_from_surface_index = true } },
    call = function(iface, fn, arg)
      if iface == "space-exploration" and fn == "get_zone_from_surface_index" then
        local idx = type(arg) == "table" and arg.surface_index or arg
        zone_calls = zone_calls + 1
        return { index = idx * 10, name = "Zone-" .. idx, type = "planet" }
      end
    end,
  }
  local c_force = { valid = true, name = "player", index = 1 }
  local cannon_ent = {
    valid = true, name = "se-delivery-cannon", unit_number = 7701, force = c_force,
    position = { x = 10, y = 20 },
    get_recipe = function() return { name = "se-delivery-cannon-pack-iron-plate" } end,
    get_inventory = function() return { valid = true, is_empty = function() return true end } end,
  }
  local receiver_ent = {
    valid = true, name = "se-delivery-cannon-chest", unit_number = 7702, force = c_force,
    position = { x = 4, y = 105 },
  }
  local s1 = { index = 1, name = "nauvis", valid = true }
  local s2 = { index = 2, name = "orbit", valid = true }
  s1.find_entities_filtered = function(q)
    if q.name == "se-delivery-cannon" then return { cannon_ent } end
    return {}
  end
  s2.find_entities_filtered = function(q)
    if q.name == "se-delivery-cannon-chest" then return { receiver_ent } end
    return {}
  end
  cannon_ent.surface, receiver_ent.surface = s1, s2
  game.surfaces = { [1] = s1, [2] = s2, nauvis = s1 }
  storage.se_cannons = nil

  local function fire(t, x, y)
    game.tick = t
    Cannons.on_effect({ effect_id = Cannons.EFFECT_ID, tick = t, surface_index = 1,
      source_position = { x = 9.5, y = 15 } })
    Cannons.on_effect({ effect_id = Cannons.PROJECTILE_EFFECT_ID, tick = t, surface_index = 2,
      target_position = { x = x, y = y } })
  end
  fire(1000, 4, 5)
  assert(storage.se_cannons.zone_cache[2] and storage.se_cannons.zone_cache[1],
    "zone_cache must be persisted in storage.se_cannons")
  assert(zone_calls == 2, "Initial firings should resolve both surface zones once")
  fire(1050, 4, 5)
  assert(zone_calls == 2, "Subsequent firings must reuse persisted storage.se_cannons.zone_cache")
  local sc = storage.se_cannons
  assert(sc.min_eta == 1120 and sc.in_flight_by_eta[1120] and sc.in_flight_by_eta[1170],
    "in_flight_by_eta and min_eta must track concurrent shots")
  Cannons.on_tick(1121)
  assert(sc.min_eta == 1170 and (sc.history[1].status == "arrived" or sc.history[1].status == "received") and sc.history[2].status == "in-flight",
    "Settling tick 1121 must settle only the eta=1120 shot and advance min_eta to 1170")

  -- Legacy save state without in_flight_by_eta migrates cleanly
  sc.in_flight_by_eta, sc.min_eta = nil, nil
  Cannons.on_tick(1169)
  assert(sc.history[2].status == "in-flight" and sc.min_eta == 1170,
    "on_tick must rebuild missing in_flight_by_eta without settling early")
  Cannons.on_tick(1171)
  assert((sc.history[2].status == "arrived" or sc.history[2].status == "received") and not next(sc.in_flight),
    "Second shot must settle at eta+1 cleanly")

  -- Query early break respects window [tick - seconds*60, tick]
  fire(1500, 4, 5)
  Cannons.on_tick(1621)
  local q = Cannons.query(c_force, s1, 1500, 1) -- since = 1440
  assert(#q.observations == 1 and q.observations[1].tick == 1500,
    "Cannons.query early break must return only in-window observations")

  script.active_mods, storage.se_cannons, remote = saved_mods, saved_cannons, saved_remote
  game.surfaces, prototypes.recipe = saved_surfaces, saved_recipes
  defines.events.on_script_trigger_effect, game.tick, defines.inventory.assembling_machine_output = saved_effect, saved_tick, saved_asm_out
end

-- 3. groups.lua: prototype rank/localised cache parity and refresh on prototype table change
do
  local saved_sg = prototypes.item_subgroup
  local info0 = Gr.info(1, "sub:x")
  local list0 = Gr.list(1)
  assert(info0 and #list0 > 0)
  prototypes.item_subgroup = {
    a = { name = "a", order = "aa" },
    x = { name = "x", order = "zz-updated", localised_name = "Updated Subgroup X" },
  }
  local info1 = Gr.info(1, "sub:x")
  assert(info1.localised_name == "Updated Subgroup X" and info1.order == 501,
    "Groups cache must refresh automatically when prototypes.item_subgroup reference changes")
  prototypes.item_subgroup = saved_sg
  Gr.info(1, "sub:x")
end

-- 4. se_transfer_panels: hs._records/hs._exchanges stripped from storage while last_records/page actions work
do
  local panel_root = player.gui.screen.add { type = "flow", name = "audit_panels_root", direction = "vertical" }
  local hs = { axis = "buckets", page = 1 }
  local jumped
  local old_jump = Endpoints.jump
  Endpoints.jump = function(_, target) jumped = target end
  local recs = {}
  for i = 1, 25 do
    recs[i] = {
      key = "rec-" .. i, tick = 1000 + i, arrival_tick = 1010 + i,
      method = "rocket", direction = "exports", status = "received",
      sender = { id = "s-" .. i, surface = game.surfaces[1], valid = true },
      receiver = { id = "r-" .. i, surface = game.surfaces[1], valid = true },
      remote = { name = "Orbit", surface = game.surfaces[1] },
      sent = { { name = "iron-plate", quality = "normal", count = i } },
      received = { { name = "iron-plate", quality = "normal", count = i } },
    }
  end
  Panels.history(panel_root, player, game.surfaces[1], 600,
    { view = "history", history = hs }, 1000, 700, { records = recs, from_tick = 900, to_tick = 1100 })
  assert(hs._records == nil and hs._exchanges == nil,
    "Full shipment records/exchanges must not be retained on storage state hs")
  assert(hs._page_records ~= nil, "Visible page records must be stored in hs._page_records")
  local page_count = 0
  for _ in pairs(hs._page_records) do page_count = page_count + 1 end
  assert(page_count <= 20 and page_count == 20, "hs._page_records must be bounded to PAGE=20")
  assert(#Panels.last_records(hs) == 25 and type(Panels.last_exchanges(hs)) == "table",
    "Weak-table accessors Panels.last_records/last_exchanges must expose rendered data")

  local function find_tagged(el, pred)
    if el.tags and pred(el.tags) then return el end
    for _, c in ipairs(el.children or {}) do
      local hit = find_tagged(c, pred)
      if hit then return hit end
    end
  end
  local expand_btn = find_tagged(panel_root, function(t) return t.se_logistics == "panel-expand" end)
  assert(expand_btn, "Expected panel-expand button in rendered history page")
  assert(Panels.on_click({ player_index = 1, element = expand_btn }, { view = "history", history = hs }))
  assert(hs.expanded == expand_btn.tags.key, "panel-expand must toggle expanded using hs._page_records")

  local jump_btn = find_tagged(panel_root, function(t) return t.se_logistics == "panel-jump" end)
  assert(jump_btn, "Expected panel-jump button in rendered history page")
  assert(Panels.on_click({ player_index = 1, element = jump_btn }, { view = "history", history = hs }))
  assert(jumped ~= nil, "panel-jump must resolve endpoint from hs._page_records")

  Endpoints.jump = old_jump
  panel_root.destroy()
end

-- 5 & 6 & 7. cells_ui.jump_target nil view, cells.on_built incremental update (no Rail.reindex), cell_flow single rate_sources
do
  local Selection = TREQ("shared.cell_selection")
  local saved_cells, saved_units = storage.production_cells, storage.cell_units
  local saved_cursor, saved_clear = player.cursor_stack, player.clear_cursor
  local saved_translate = player.request_translation
  local saved_reindex = Rail.reindex
  local reindex_calls = 0
  Rail.reindex = function(...) reindex_calls = reindex_calls + 1; return saved_reindex(...) end

  storage.production_cells, storage.cell_units = nil, nil
  player.cursor_stack = { valid_for_read = true, name = Selection.tool, clear = function() end,
    set_stack = function(stack) player.cursor_stack.name = stack.name; return true end }
  player.clear_cursor = function() return true end
  player.request_translation = function() return 1 end

  local m1 = { valid = true, type = "assembling-machine", name = "am", unit_number = 9101,
    surface = game.surfaces[1], surface_index = 1, force = game.forces.player,
    position = { x = 10, y = 10 }, get_recipe = function() return { name = "copper-cable" } end,
    crafting_speed = 1, productivity_bonus = 0 }
  local m2 = { valid = true, type = "assembling-machine", name = "am", unit_number = 9102,
    surface = game.surfaces[1], surface_index = 1, force = game.forces.player,
    position = { x = 14, y = 10 }, get_recipe = function() return { name = "electronic-circuit" } end,
    crafting_speed = 1, productivity_bonus = 0 }
  local m3 = { valid = true, type = "assembling-machine", name = "am", unit_number = 9103,
    surface = game.surfaces[1], surface_index = 1, force = game.forces.player,
    position = { x = 18, y = 10 }, get_recipe = function() return { name = "iron-gear-wheel" } end,
    crafting_speed = 1, productivity_bonus = 0 }

  local function make_cell(ents, name)
    player.cursor_stack.name = Selection.tool
    Cells.on_selected { item = Selection.tool, player_index = player.index, surface = game.surfaces[1], entities = ents }
    local win = player.gui.screen[Cells.NAME]
    win.ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = name
    assert(Cells.on_click(player, { valid = true, tags = { ssk_cell = "save" } }))
  end
  make_cell({ m1, m2, m3 }, "Audit Parent")
  local parent_id = next(storage.production_cells.records)
  make_cell({ m2 }, "Child A")
  local child_a_id
  for id in pairs(storage.production_cells.records) do if id ~= parent_id then child_a_id = id end end
  make_cell({ m3 }, "Child B")
  local child_b_id
  for id in pairs(storage.production_cells.records) do if id ~= parent_id and id ~= child_a_id then child_b_id = id end end
  local parent_cell = storage.production_cells.records[parent_id]
  storage.production_cells.records[child_a_id].parent_id = parent_id
  storage.production_cells.records[child_b_id].parent_id = parent_id
  Cells.reindex()

  -- Test 5: CellsUI.jump_target when current_view == nil
  local ui_state = { ids = { parent_id }, maps = {}, fitted = nil }
  assert(CellsUI.current_view(ui_state) == nil)
  local view = CellsUI.jump_target(player, ui_state)
  assert(view and view.surface == 1 and view.x and view.y and view.zoom,
    "UI.jump_target must synthesize UI.map_view when current_view is nil")
  Outlines.clear(player)

  -- Test 6: Cells.on_built replacement updates members/cell_units/slots incrementally without Rail.reindex
  reindex_calls = 0
  m1.valid = false
  local rep = { valid = true, type = "assembling-machine", name = "am", unit_number = 9199,
    surface = game.surfaces[1], surface_index = 1, force = game.forces.player,
    position = { x = 10, y = 10 }, get_recipe = function() return { name = "copper-cable" } end,
    crafting_speed = 1, productivity_bonus = 0 }
  Cells.on_built(rep)
  assert(reindex_calls == 0, "Cells.on_built replacement must not invoke full Rail.reindex")
  assert(parent_cell.members[9101] == nil and parent_cell.members[9199] == rep,
    "Cells.on_built must replace the invalidated member in parent record")
  assert(storage.cell_units[9101] == nil and storage.cell_units[9199] and storage.cell_units[9199][1] == parent_id,
    "Incremental Sampler membership must drop dead unit and register replacement unit")

  -- Test 7: Flow.build parent + children shares one Sampler.rate_sources call per surface
  local saved_rate_sources = Sampler.rate_sources
  local rs_calls = 0
  Sampler.rate_sources = function(...) rs_calls = rs_calls + 1; return saved_rate_sources(...) end
  local pgraph = Flow.build(parent_id, { surface = 1, period = 600, mode = "measured" })
  assert(rs_calls == 1, "Flow.build must share one Sampler.rate_sources call across parent and children: got " .. rs_calls)
  assert(pgraph and pgraph.nodes["recipe/cell-" .. child_a_id] and pgraph.nodes["recipe/cell-" .. child_b_id],
    "Parent cell Flow.build must emit child overview nodes cleanly")

  Sampler.rate_sources = saved_rate_sources
  Rail.reindex = saved_reindex
  if player.gui.screen[Cells.NAME] then player.gui.screen[Cells.NAME].destroy() end
  storage.production_cells, storage.cell_units = saved_cells, saved_units
  player.cursor_stack, player.clear_cursor, player.request_translation = saved_cursor, saved_clear, saved_translate
  Sampler.set_cell_membership(nil, nil)
  if saved_cells then Cells.reindex() end
end

-- 8. transfers_ui flow_signature, view.lua keep_layout + Focus render_fingerprint + tiers() cycles, Neighborhood adjacency
do
  -- 8a. TransfersUI.render skips canvas rebuild when flow_signature unchanged and redraws on size change
  local saved_avail, saved_pview = Transfers.available, Transfers.platform_view
  Transfers.available = function() return true end
  local mock_result = {
    platforms = { { id = "plat-1", name = "Test Ship", surface = game.surfaces[1] } },
    platform = { id = "plat-1", name = "Test Ship", location = "nauvis" },
    loading = { { endpoint = { id = "s:1", surface = game.surfaces[1], kind = "surface", name = "Nauvis" },
      weight = 100, unknown_weight = false, items = { { name = "iron-plate", count = 100 } } } },
    unloading = {},
    loaded = { weight = 100, unknown_weight = false, items = {} },
    unloaded = { weight = 0, unknown_weight = false, items = {} },
    made = { items = {}, seconds = 60, weight = 0, unknown_weight = false },
    covered_seconds = 60, buckets = {}, selected_records = {},
  }
  Transfers.platform_view = function() return mock_result end
  local host = player.gui.screen.add { type = "flow", name = "audit_transfers_host", direction = "vertical" }
  local tstate = { view = "flow" }
  TransfersUI.render(host, player, 600, tstate, 900, 600)
  local canvas = host.ssk_transfers.split.tab_row.ssk_transfer_tabs.ssk_transfer_flow.content.graph.canvas
  local first_child = canvas.children[1]
  local first_sig = canvas.tags.transfer_graph
  assert(first_child and first_sig, "Initial TransfersUI render must populate flow canvas and transfer_graph tag")
  TransfersUI.render(host, player, 600, tstate, 900, 600)
  assert(canvas.children[1] == first_child and canvas.tags.transfer_graph == first_sig,
    "Unchanged flow_signature must skip parent.clear() and keep existing canvas widgets")
  -- Destroy outer frame and re-render with altered viewport width -> signature must differ
  host.clear()
  TransfersUI.render(host, player, 600, tstate, 1100, 600)
  local second_sig = host.ssk_transfers.split.tab_row.ssk_transfer_tabs.ssk_transfer_flow.content.graph.canvas.tags.transfer_graph
  assert(second_sig ~= first_sig, "Changing width/viewport must change flow_signature and force redraw")
  host.destroy()
  Transfers.available, Transfers.platform_view = saved_avail, saved_pview

  -- 8b. View.build Focus render_fingerprint + keep_layout + cyclic tiers() determinism
  local us = {
    sidx = 1, period = 600, view = "full", layout = "lanes", heights = "sqrt", lines = "metro",
    hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {}, show_labels = true,
  }
  local L1 = View.build(player, us, 1200, 700, nil, false)
  assert(L1 and us.layout_snapshot and us.layout_snapshot.fit, "Full View.build must populate layout_snapshot.fit")
  local saved_scale = us.layout_snapshot.scale
  us.render_fingerprint = nil -- force re-layout without auto short-circuit
  local L2 = View.build(player, us, 1200, 700, nil, false)
  assert(us.keep_layout == true and L2 and L2.scale == saved_scale,
    "Unchanged signature must set us.keep_layout=true and preserve layout scale")

  -- Focus view enables render_fingerprint caching when automatic=true
  local us_focus = {
    sidx = 1, period = 600, view = "focus", focus = "item/iron-plate", focus_steps = 2, zoom = 1,
    hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {}, show_labels = true,
  }
  local LF1 = View.build(player, us_focus, 1200, 700, nil, false)
  assert(LF1 and LF1.render_fingerprint, "Focus build must compute render_fingerprint")
  us_focus.render_fingerprint = LF1.render_fingerprint
  local LF2 = View.build(player, us_focus, 1200, 700, nil, true)
  assert(LF2 == nil, "Automatic Focus rebuild with identical render_fingerprint must skip full layout")

  -- Cycle breaking in tiers() with synthetic cyclic cell graph
  local function mk_cyclic()
    local nodes = {
      ["item/a"] = { key = "item/a", kind = "item", prod = 10, cons = 10, loops = {}, contrib = {} },
      ["recipe/r1"] = { key = "recipe/r1", kind = "recipe", prod = 10, cons = 10, loops = {}, contrib = {} },
      ["item/c"] = { key = "item/c", kind = "item", prod = 10, cons = 10, loops = {}, contrib = {} },
      ["recipe/r2"] = { key = "recipe/r2", kind = "recipe", prod = 10, cons = 10, loops = {}, contrib = {} },
    }
    local links = {
      ["item/a>recipe/r1"] = { from = "item/a", to = "recipe/r1", rate = 10 },
      ["recipe/r1>item/c"] = { from = "recipe/r1", to = "item/c", rate = 10 },
      ["item/c>recipe/r2"] = { from = "item/c", to = "recipe/r2", rate = 10 },
      ["recipe/r2>item/a"] = { from = "recipe/r2", to = "item/a", rate = 2 },
    }
    return { nodes = nodes, links = links }
  end
  local uc1 = { sidx = 1, period = 600, view = "full", hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {}, show_labels = true }
  local uc2 = { sidx = 1, period = 600, view = "full", hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {}, show_labels = true }
  local LC1 = View.build(player, uc1, 1000, 600, mk_cyclic(), false)
  local LC2 = View.build(player, uc2, 1000, 600, mk_cyclic(), false)
  assert(LC1 and LC2 and LC1.cols and #LC1.cols == #LC2.cols,
    "Cyclic tiers() cycle-breaking must produce deterministic columns")

  -- 8c. Neighborhood.build prebuilt adjacency parity
  local m = Model.build(1, 600)
  local gnodes, glinks = {}, {}
  local function node(k)
    gnodes[k] = gnodes[k] or { key = k, kind = k:match("^(%a+)/"), prod = 1, cons = 1, loops = {}, contrib = {} }
  end
  for l in pairs(m.rates and m.rates.links or {}) do
    local a, b = l:match("^(.+)>(.+)$")
    node(a); node(b)
    glinks[l] = { from = a, to = b, rate = 1 }
  end
  if gnodes["item/iron-plate"] then
    local nn, nl = Neighborhood.build(gnodes, glinks, m, "item/iron-plate", 2)
    assert(nn["item/iron-plate"] and next(nl) ~= nil, "Neighborhood.build must produce center node and links")
  end
end

-- 9. MaterialPicker: open catalog cache reuses tabs and unchanged result grids without UI change
do
  local Picker = TREQ("scripts.material_picker")
  local orig_iron = rawget(prototypes.item, "iron-plate")
  local orig_copper = rawget(prototypes.item, "copper-plate")
  rawset(prototypes.item, "iron-plate", { name = "iron-plate", order = "a", group = { name = "intermediate-products", order = "a" }, subgroup = { name = "raw-material", order = "a" } })
  rawset(prototypes.item, "copper-plate", { name = "copper-plate", order = "b", group = { name = "intermediate-products", order = "a" }, subgroup = { name = "raw-material", order = "a" } })
  Picker.open(player, "focus", "item/iron-plate")
  local dlg = player.gui.screen.ssk_material_picker
  local tabs = dlg.ssk_material_inner.ssk_group_scroll.ssk_groups
  local first_tab = tabs.children[1]
  local grid = dlg.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll.ssk_results
  dlg.ssk_title.ssk_query.text = "iron"
  assert(Picker.on_text_changed({ player_index = player.index, element = dlg.ssk_title.ssk_query }))
  assert(#tabs.children > 0 and tabs.children[1] == first_tab,
    "Searching in MaterialPicker must update group tabs in place without rebuilding them")
  local first_slot = grid.children[1]
  assert(first_slot and #grid.tags.keys >= 1)
  dlg.ssk_title.ssk_query.text = "IRON"
  assert(Picker.on_text_changed({ player_index = player.index, element = dlg.ssk_title.ssk_query }))
  assert(grid.children[1] == first_slot,
    "Unchanged filtered results must skip grid.clear() and reuse existing slot widgets")
  Picker.close(player)
  rawset(prototypes.item, "iron-plate", orig_iron)
  rawset(prototypes.item, "copper-plate", orig_copper)
end

-- 10. MiningDetails: MP-safe storage.mining_cache, explicit fresh rescan, and drill removal invalidation
do
  local saved_get_filtered = prototypes.get_entity_filtered
  local saved_find = game.surfaces[1].find_entities_filtered
  local saved_cache = storage.mining_cache
  local saved_tick = game.tick
  local drill_scans, active_drills = 0, {
    { name = "electric-mining-drill", mining_target = { valid = true, type = "resource", name = "iron-ore" } },
  }
  prototypes.get_entity_filtered = function()
    return {
      ["iron-ore"] = {
        localised_name = "Iron ore",
        mineable_properties = { minable = true, products = { { type = "item", name = "iron-ore" } } },
      },
    }
  end
  game.surfaces[1].find_entities_filtered = function(q)
    if q.type == "mining-drill" then
      drill_scans = drill_scans + 1
      return active_drills
    end
    return saved_find(q)
  end
  local Mining = assert(loadfile("scripts/mining_details.lua"))()
  storage.mining_cache = nil
  game.tick = 5000
  local made1 = Mining.sources_and_uses(1, "item/iron-ore", game.forces.player, false)
  assert(drill_scans == 1 and #made1 == 1 and made1[1].drills["electric-mining-drill"] == 1)
  assert(type(storage.mining_cache) == "table" and next(storage.mining_cache) ~= nil,
    "Mining.sources_and_uses must persist drill cache in storage.mining_cache (MP-safe)")
  local cached_key = next(storage.mining_cache)
  local first_entry = storage.mining_cache[cached_key]
  -- Drill removed at tick 5001: background cached read still uses cache while explicit fresh read sees 0.
  active_drills = {}
  game.tick = 5001
  local bg = Mining.sources_and_uses(1, "item/iron-ore", game.forces.player, false)
  assert(drill_scans == 1 and storage.mining_cache[cached_key] == first_entry and bg[1].drills["electric-mining-drill"] == 1,
    "Background reads within DRILL_CACHE_TICKS must reuse storage.mining_cache")
  local explicit = Mining.sources_and_uses(1, "item/iron-ore", game.forces.player, true)
  assert(drill_scans == 2 and explicit[1].drills == nil,
    "Explicit fresh read must reflect removed drill on the very next tick")
  -- Also test Mining.invalidate clears cached count for background reads too.
  active_drills = { { name = "electric-mining-drill", mining_target = { valid = true, type = "resource", name = "iron-ore" } } }
  game.tick = 5002
  assert(Mining.sources_and_uses(1, "item/iron-ore", game.forces.player, false)[1].drills == nil)
  Mining.invalidate(1)
  local rebuilt = Mining.sources_and_uses(1, "item/iron-ore", game.forces.player, false)
  assert(drill_scans == 3 and rebuilt[1].drills["electric-mining-drill"] == 1,
    "Mining.invalidate must clear cached drill counts immediately")
  game.tick = saved_tick
  storage.mining_cache = saved_cache
  prototypes.get_entity_filtered = saved_get_filtered
  game.surfaces[1].find_entities_filtered = saved_find
end

-- 11. Checkpoint: SE cannon upgraded save + new projectile before first on_tick both settle
do
  local saved_mods, saved_cannons, saved_remote = script.active_mods, storage.se_cannons, remote
  local saved_surfaces, saved_recipes = game.surfaces, prototypes.recipe
  local saved_effect, saved_tick = defines.events.on_script_trigger_effect, game.tick
  script.active_mods = { ["space-exploration"] = "0.7.64" }
  defines.events.on_script_trigger_effect = 99
  local c_force = { valid = true, name = "player", index = 1 }
  local s1 = { index = 1, name = "nauvis", valid = true }
  local s2 = { index = 2, name = "orbit", valid = true }
  local cannon_ent = {
    valid = true, name = "se-delivery-cannon", unit_number = 7801, force = c_force,
    position = { x = 10, y = 20 }, surface = s1,
    get_recipe = function() return { name = "se-delivery-cannon-pack-iron-plate" } end,
    get_inventory = function() return { valid = true, is_empty = function() return true end } end,
  }
  local receiver_ent = {
    valid = true, name = "se-delivery-cannon-chest", unit_number = 7802, force = c_force,
    position = { x = 4, y = 105 }, surface = s2,
  }
  s1.find_entities_filtered = function(q) return q.name == "se-delivery-cannon" and { cannon_ent } or {} end
  s2.find_entities_filtered = function(q) return q.name == "se-delivery-cannon-chest" and { receiver_ent } or {} end
  game.surfaces = { [1] = s1, [2] = s2, nauvis = s1 }
  remote = {
    interfaces = { ["space-exploration"] = { get_zone_from_surface_index = true } },
    call = function(_, _, arg)
      local idx = type(arg) == "table" and arg.surface_index or arg
      return { index = idx * 10, name = "Zone-" .. idx, type = "planet" }
    end,
  }
  -- Simulate an upgraded pre-bucket save with a saved shot already in_flight (no in_flight_by_eta)
  local saved_shot = {
    id = 50, tick = 2000, kind = "cannon_firing_effect", shot_count = 1,
    sender = { force = c_force, surface = s1, position = { x = 10, y = 20 }, valid = true },
    sent = { { name = "iron-plate", quality = "normal", count = 100 } },
    destination = { surface = s2, zone = 20, name = "Zone-2", position = { x = 4, y = 105 } },
    eta = 2120, status = "in-flight",
  }
  storage.se_cannons = {
    version = 1, history = { [1] = saved_shot }, first = 1, count = 1, serial = 50,
    start_tick = 1, dropped = {}, in_flight = { [50] = saved_shot }, in_flight_by_eta = nil, zone_cache = {},
  }
  -- Fire a new projectile BEFORE C.on_tick runs
  game.tick = 2010
  Cannons.on_effect({ effect_id = Cannons.EFFECT_ID, tick = 2010, surface_index = 1, source_position = { x = 9.5, y = 15 } })
  Cannons.on_effect({ effect_id = Cannons.PROJECTILE_EFFECT_ID, tick = 2010, surface_index = 2, target_position = { x = 4, y = 5 } })
  local new_shot = storage.se_cannons.history[2]
  new_shot.sent = new_shot.sent or { { name = "iron-plate", quality = "normal", count = 50 } }
  assert(storage.se_cannons.in_flight_by_eta[2120] and storage.se_cannons.in_flight_by_eta[2120][50] == saved_shot,
    "track_in_flight must index legacy in_flight shots before inserting the new shot")
  Cannons.on_tick(2121)
  Cannons.on_tick(2131)
  assert(saved_shot.status == "received" and saved_shot.received and saved_shot.received[1].count == 100,
    "Saved shot from pre-upgrade in_flight must settle and record receipt")
  assert(new_shot.status == "received" and new_shot.received and new_shot.received[1].count == 50,
    "New post-upgrade shot must also settle and record receipt")
  assert(not next(storage.se_cannons.in_flight))

  script.active_mods, storage.se_cannons, remote = saved_mods, saved_cannons, saved_remote
  game.surfaces, prototypes.recipe = saved_surfaces, saved_recipes
  defines.events.on_script_trigger_effect, game.tick = saved_effect, saved_tick
end

-- 12. Checkpoint: Balance Flow and Focus tooltips reflect stock change (123 -> 456) on live auto refresh
do
  local SK = TREQ("scripts.sankey_ui")
  local saved_stock, saved_basis = storage.stock, storage.stock_basis
  storage.stock_basis = "physical-storage-v2"
  storage.stock = { { tick = game.tick, s = { [1] = { ["item/iron-plate"] = 123 } } } }

  local function find_tooltip(el, needle)
    if el.tooltip then
      local txt = type(el.tooltip) == "string" and el.tooltip or LOC(el.tooltip)
      if type(txt) == "string" and txt:find(needle, 1, true) then return true end
    end
    for _, c in ipairs(el.children or {}) do
      if find_tooltip(c, needle) then return true end
    end
    return false
  end

  local host = player.gui.screen.add { type = "flow", name = "audit_stock_tip_host", direction = "vertical" }
  for _, case in ipairs({
    { name = "bal", us = { view = "detail", sidx = 1, period = 600, neighborhood = true, focus = "item/iron-plate", sel = "item/iron-plate", input_depth = 1, live = true, hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {} } },
    { name = "focus", us = { view = "focus", sidx = 1, period = 600, focus = "item/iron-plate", sel = "item/iron-plate", focus_steps = 2, zoom = 1, live = true, hidden = {}, collapsed = {}, colors = {}, pos = {}, gpos = {}, lpos = {} } },
  }) do
    storage.stock[1].s[1]["item/iron-plate"] = 123
    local pane = host.add { type = "flow", name = case.name, direction = "vertical" }
    SK.fill(player, pane, case.us, 1000, 600, true, false)
    assert(find_tooltip(pane, "123"), case.name .. " initial tooltip must display stock 123")
    storage.stock[1].s[1]["item/iron-plate"] = 456
    SK.fill(player, pane, case.us, 1000, 600, false, true)
    assert(find_tooltip(pane, "456") and not find_tooltip(pane, "123"),
      case.name .. " live auto-refresh tooltip must update from stock 123 to 456 cleanly")
    assert(case.us.focus == "item/iron-plate" and case.us.sel == "item/iron-plate",
      case.name .. " live refresh must preserve selection")
  end
  host.destroy()
  storage.stock, storage.stock_basis = saved_stock, saved_basis
end

-- 13. Checkpoint: Cells Flow UI.jump_target uses fresh fit after deleting distant cell while keeping valid player pan/zoom
do
  local Selection = TREQ("shared.cell_selection")
  local saved_cells, saved_units = storage.production_cells, storage.cell_units
  local saved_cursor, saved_clear = player.cursor_stack, player.clear_cursor
  local saved_translate = player.request_translation
  storage.production_cells, storage.cell_units = nil, nil
  player.cursor_stack = { valid_for_read = true, name = Selection.tool, clear = function() end,
    set_stack = function(stack) player.cursor_stack.name = stack.name; return true end }
  player.clear_cursor = function() return true end
  player.request_translation = function() return 1 end

  local function mk(unit, x)
    return { valid = true, type = "assembling-machine", name = "am", unit_number = unit,
      surface = game.surfaces[1], surface_index = 1, force = game.forces.player,
      position = { x = x, y = 0 }, get_recipe = function() return { name = "iron-plate" } end,
      crafting_speed = 1, productivity_bonus = 0 }
  end
  local function add_cell(unit, x, name)
    player.cursor_stack.name = Selection.tool
    Cells.on_selected { item = Selection.tool, player_index = player.index, surface = game.surfaces[1], entities = { mk(unit, x) } }
    local win = player.gui.screen[Cells.NAME]
    win.ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = name
    assert(Cells.on_click(player, { valid = true, tags = { ssk_cell = "save" } }))
  end
  add_cell(9301, 0, "Origin Cell")
  local id0 = next(storage.production_cells.records)
  add_cell(9302, 200, "Distant Cell")
  local id200
  for id in pairs(storage.production_cells.records) do if id ~= id0 then id200 = id end end

  local cstate = { sidx = 1, ids = { id0, id200 }, maps = {} }
  local initial_fit = CellsUI.jump_target(player, cstate)
  assert(math.abs(initial_fit.x - 100) < 1e-6, "Midpoint between x=0 and x=200 must start at x=100")
  -- Delete distant cell while on Flow tab (without CellsUI.fill running)
  storage.production_cells.records[id200] = nil
  local updated_fit = CellsUI.jump_target(player, cstate)
  assert(math.abs(updated_fit.x - 0) < 1e-6,
    "UI.jump_target must recompute current fit (x=0) after distant cell deletion, not reuse stale x=100")
  -- Preserve valid player-set pan and zoom on matching surface
  cstate.maps = { all = { x = 42, y = -9, surface = 1, zoom = 0.5 } }
  local kept_pan = CellsUI.jump_target(player, cstate)
  assert(kept_pan.x == 42 and kept_pan.y == -9 and kept_pan.zoom == 0.5,
    "UI.jump_target must preserve valid player-set pan and zoom")
  Outlines.clear(player)

  if player.gui.screen[Cells.NAME] then player.gui.screen[Cells.NAME].destroy() end
  storage.production_cells, storage.cell_units = saved_cells, saved_units
  player.cursor_stack, player.clear_cursor, player.request_translation = saved_cursor, saved_clear, saved_translate
  Sampler.set_cell_membership(nil, nil)
  if saved_cells then Cells.reindex() end
end

-- 14. Checkpoint: SE history coverage per-method truncation parity (Data.narrow + SELogisticsUI)
do
  local Data = TREQ("scripts.se_transfer_data")
  local SEView = TREQ("scripts.se_logistics_ui")
  local base = {
    records = {}, materials = {}, qualities = {}, unpaired = {},
    from_tick = 100, to_tick = 700, seconds = 10,
    rockets_truncated = false, cannons_truncated = true, truncated = true,
    coverage = { rocket = 10, cannon = 5 },
  }
  assert(Data.narrow(base, { method = "rocket" }).truncated == false,
    "Rocket-only filter must not inherit cannon truncation")
  assert(Data.narrow(base, { method = "cannon" }).truncated == true,
    "Cannon-only filter must report cannon truncation")
  assert(Data.narrow(base, {}).truncated == true,
    "Unfiltered query must report truncation when either method is truncated")

  local base_r = {
    records = {}, materials = {}, qualities = {}, unpaired = {},
    from_tick = 100, to_tick = 700, seconds = 10,
    rockets_truncated = true, cannons_truncated = false, truncated = true,
    coverage = { rocket = 5, cannon = 10 },
  }
  assert(Data.narrow(base_r, { method = "cannon" }).truncated == false,
    "Cannon-only filter must not inherit rocket truncation")
  assert(Data.narrow(base_r, { method = "rocket" }).truncated == true,
    "Rocket-only filter must report rocket truncation")

  local saved_query = Data.query
  Data.query = function() return base end
  local se_host = player.gui.screen.add { type = "flow", name = "audit_se_cov_host", direction = "vertical" }
  local s_valid = { index = 1, name = "nauvis", valid = true, find_entities_filtered = function() return {} end }
  local state_rocket = { view = "items", method = "rocket" }
  SEView.render(se_host, player, s_valid, 600, state_rocket, 1000, 600)
  local cov_rocket = LOC(se_host.ssk_se_logistics.heading.se_coverage.caption)
  assert(not cov_rocket:find("incomplete", 1, true) and cov_rocket:find("10 s", 1, true),
    "SE Items view filtered to rockets must not show incomplete cannon warning: " .. cov_rocket)
  local state_cannon = { view = "items", method = "cannon" }
  SEView.render(se_host, player, s_valid, 600, state_cannon, 1000, 600)
  assert(LOC(se_host.ssk_se_logistics.heading.se_coverage.caption):find("incomplete", 1, true),
    "SE Items view filtered to cannons must report incomplete history")
  local state_all = { view = "items" }
  SEView.render(se_host, player, s_valid, 600, state_all, 1000, 600)
  assert(LOC(se_host.ssk_se_logistics.heading.se_coverage.caption):find("incomplete", 1, true),
    "Unfiltered SE view must report incomplete history when either provider is truncated")
  se_host.destroy()
  Data.query = saved_query
end

print("AUDIT PERF TESTS OK")
