-- Injected into the private reporter-save mod copy only. Uses the factory's
-- actual sampler/history; it never substitutes production rates or recipes.
local T = {}
local SK = require("scripts.sankey_ui")
local Check = require("scripts.gui_interaction_checks")
local Canvas = require("scripts.canvas")
local Config = require("scripts.modded_gui_config")
local PERIOD = Config.period or 600
local WARM_SECONDS = Config.warm_seconds or 600
local RESOLUTION = Config.resolution or { 2560, 1440 }
local cases = {}
for _, renderer in ipairs({ "poly", "sprites" }) do
  for _, tab in ipairs({ "balance", "focus", "sankey" }) do
    cases[#cases + 1] = { tab=tab, renderer=renderer, name=tab .. "-" .. renderer }
  end
end

local function write(player, name, value)
  helpers.write_file("modded-gui/" .. name .. ".json", helpers.table_to_json(value), false, player.index)
end

local function find(element, predicate)
  if predicate(element) then return element end
  for _, child in ipairs(element.children) do
    local found = find(child, predicate)
    if found then return found end
  end
end

local function first_player()
  local result
  for _, player in pairs(game.connected_players) do
    if not result or player.index < result.index then result = player end
  end
  return result
end

local function hide_other_screen_roots(player, state)
  for _, root in ipairs(player.gui.screen.children) do
    if root.name ~= "ssk_main" and root.visible then
      state.suppressed_screen_roots[#state.suppressed_screen_roots + 1] = {
        index=root.index, name=root.name, type=root.type, tick=game.tick, previous_visible=true,
      }
      root.visible = false
    end
  end
end

local function valid_material(key)
  if type(key) ~= "string" then return false end
  local kind, name = key:match("^(%a+)/(.+)$")
  return (kind == "item" or kind == "fluid") and prototypes[kind][name] ~= nil
    and storage.graph and storage.graph.nodes[key] ~= nil
end

local function choose_material(rates)
  local connected = {}
  if Config.reuse_recorded then
    for name, rate in pairs(rates.recipes) do
      local recipe = storage.graph.recipes[name]
      if recipe and rate.cps > 0 then
        for _, part in ipairs(recipe.ingredients) do connected[part.key] = true end
        for _, part in ipairs(recipe.products) do connected[part.key] = true end
      end
    end
  end
  local best, activity = nil, -1
  for key, node in pairs(rates.nodes) do
    local total = (node.prod or 0) + (node.cons or 0)
    if valid_material(key) and total > 0 and (not Config.reuse_recorded or connected[key]) then
      if key == "item/iron-plate" then return key end
      if total > activity or (total == activity and (not best or key < best)) then
        best, activity = key, total
      end
    end
  end
  return assert(best, "Reporter factory has no active item/fluid on the connected player's surface after warmup")
end

local function recorded_factory_surface(Sampler)
  local best, best_count = nil, 0
  for _, surface in pairs(game.surfaces) do
    if surface.name ~= "ssk-canvas" then
      local rates, count = Sampler.rates(surface.index, PERIOD), 0
      for name, rate in pairs(rates.recipes) do
        if rate.cps > 0 and storage.graph.recipes[name] then count = count + 1 end
      end
      if count > best_count or (best and count == best_count and surface.index < best.index) then
        best, best_count = surface, count
      end
    end
  end
  return assert(best, "The input save has no recorded recipe flow to reuse")
end

local function reset_chart(state, renderer)
  state.live, state.renderer, state.show_labels = false, renderer, true
  state.layout, state.heights, state.lines, state.color_mode = "clean", "sqrt", "curves", "destination"
  state.sel, state.pinned, state.settings_open, state.layout_snapshot = nil, nil, nil, nil
  state.tier_lo, state.tier_hi, state.auto_rank = nil, nil, nil
  state.hidden, state.collapsed, state.pos, state.gpos, state.lpos = {}, {}, {}, {}, {}
  state.zoom, state.center_pending, state.fit_pending = 1, nil, nil
  state.chart_zoom, state.chart_fit, state.chart_viewport = nil, nil, nil
end

local function open_case(UI, player, state, case)
  hide_other_screen_roots(player, state)
  if not storage.ui[player.index] then UI.open(player) end
  local us = storage.ui[player.index]
  us.tab_id, us.surface, us.period = case.tab, state.surface, PERIOD
  us.view, us.preset, us.tier_mode = "detail", "all", "depth"
  us.bal_filter, us.bal_group, us.bal_sort = "all", nil, "priority"
  us.bal_mode, us.bal_details = "flow", false
  reset_chart(us, case.renderer)
  local balance, focus = SK.balance_state(us), SK.focus_state(us)
  for _, chart in ipairs({ balance, focus }) do
    reset_chart(chart, case.renderer)
    chart.view, chart.focus, chart.focus_steps, chart.input_depth = "focus", state.focus, 2, 1
    chart.focus_hist, chart.focus_forward = {}, {}
  end
  balance.neighborhood, focus.neighborhood = true, nil
  local profiler=helpers.create_profiler()
  UI.open(player)
  profiler.stop()
  state.open_profile=tostring(profiler)
  player.gui.screen.ssk_main.bring_to_front()
end

function T.init()
  if remote.interfaces.freeplay and remote.interfaces.freeplay.set_skip_intro then
    remote.call("freeplay", "set_skip_intro", true)
  end
  game.tick_paused = false
end

function T.unpause()
  local state=storage.modded_gui_test
  if state and not state.done then game.tick_paused=false end
end

local viewport_steps = {"initial", "pan", "zoom", "edge", "fit"}
local function viewport_step(UI, player, state)
  local index = #state.viewport + 1
  local name = viewport_steps[index]
  if not name then return false end
  local us = storage.ui[player.index]
  if name == "initial" and not state.viewport_prepared then
    settings.get_player_settings(player)["ssk-live-sankey-overview"] = {value=true}
    open_case(UI, player, state, {tab="sankey", renderer="sprites"})
    us = storage.ui[player.index]
    us.chart_fit, us.chart_zoom, us.chart_viewport = false, 1.5, nil
    UI.refresh(player, false, false, true, true)
    state.viewport_prepared, state.next_tick = true, game.tick + 20
    return true
  end
  local root = assert(player.gui.screen.ssk_main)
  local overview = assert(find(root,function(e) return e.name=="ssk_overview" end))
  local canvas = assert(find(root,function(e) return e.name=="ssk_canvas" end))
  local pane = canvas.parent
  local chart = pane.parent.parent.parent.parent
  local function click(action)
    local e = assert(find(root,function(el) return el.tags.ssk_sk==action end))
    assert(UI.on_click{player_index=player.index,element=e})
  end
  local v = assert(us.chart_viewport)
  if not state.viewport_positioned then
    if name == "pan" then
      local x, y = math.floor(v.max_x * .35), math.floor(v.max_y * .35)
      assert(x>0 and y>0,"Real factory must overflow both viewport axes")
      assert(SK.pan_to(player,chart,us,x,y))
      UI.on_chart_wheel({player_index=player.index,element=pane},48,48)
      assert(v.x==x+48 and v.y==y+48)
    elseif name == "zoom" then
      local x, y, zoom = (v.x + v.w/2)/v.zoom, (v.y + v.h/2)/v.zoom, v.zoom
      for _=1,3 do click("zoom_in") end
      v = us.chart_viewport
      assert(v.zoom>zoom)
      assert(math.abs((v.x+v.w/2)/v.zoom-x)<2 and math.abs((v.y+v.h/2)/v.zoom-y)<2,
        "Zoom should preserve the panned center")
    elseif name == "edge" then
      local visual
      for _, candidate in pairs(storage.sk_render[player.index].node_visuals) do
        local b=candidate.icon_bounds
        if b and b[1]>8 and b[1]<v.max_x and b[2]>8 and b[2]<v.max_y then visual=candidate; break end
      end
      assert(visual,"Fixture needs an icon that can cross the viewport edge")
      local b = visual.icon_bounds
      local y = math.max(0, math.floor(b[2] - v.h/4))
      assert(SK.pan_to(player,chart,us,b[1]-8,y))
      assert(visual.icon.visible, "Unclipped icon should remain available")
      assert(SK.pan_to(player,chart,us,math.floor((b[1]+b[3])/2),y))
      assert(not visual.icon.visible and visual.icon.parent.ignored_by_interaction,
        "Clipped icon chrome must be hidden and click-through")
    elseif name == "fit" then
      click("zoom_fit")
      v=us.chart_viewport
      assert(v.x==0 and v.y==0 and v.max_x==0 and v.max_y==0,"Fit should display the entire chart")
    end
    state.viewport_positioned, state.next_tick = true, game.tick + 20
    return true
  end
  assert(canvas.style.left_margin==-v.x and canvas.style.top_margin==-v.y,"Native chart pan and viewport state diverged")
  local outline = overview.ssk_overview_map.ssk_viewport_outline
  local s = outline.children[1].style
  assert(outline.visible and outline.ignored_by_interaction)
  local previous = state.viewport[index-1]
  if name == "pan" then assert(s.left_margin>previous.outline_x and s.top_margin>previous.outline_y) end
  if name == "zoom" then assert(s.minimal_width<previous.outline_width,"Viewport outline should shrink on zoom") end
  state.viewport[index] = {name=name,x=v.x,y=v.y,zoom=v.zoom,
    outline_x=s.left_margin,outline_y=s.top_margin,outline_width=s.minimal_width}
  game.take_screenshot{player=player,path="modded-gui/viewport-"..name..".png",
    resolution=RESOLUTION,show_gui=true,force_render=true}
  state.viewport_positioned, state.next_tick = false, game.tick + 20
  return true
end

function T.tick(UI, Sampler)
  local player = first_player()
  if not player then return end
  local state = storage.modded_gui_test
  if not state then
    UI.close(player)
    state = { start_tick=game.tick, player_index=player.index, phase="warm", step=1, cases={},
      previous_speed=game.speed, suppressed_screen_roots={}, failures={} }
    storage.modded_gui_test = state
    state.opened_gui_type_at_start=player.opened_gui_type
    state.controller_at_start=player.controller_type
    local saved_surface = Config.reuse_recorded and recorded_factory_surface(Sampler) or player.surface
    state.saved_surface = Config.reuse_recorded and saved_surface.index or nil
    state.saved_coverage=Sampler.coverage(saved_surface.index,PERIOD)
    if Config.reuse_recorded then assert(state.saved_coverage>0,"The input save has no recorded history to reuse") end
    player.opened=nil
    hide_other_screen_roots(player,state)
    game.tick_paused, game.speed = false, Config.warm_speed or 64
    write(player,"warmup-start",{tick=game.tick,opened_gui_type=state.opened_gui_type_at_start,
      suppressed_screen_roots=state.suppressed_screen_roots})
    log("MODDED GUI WARMUP START " .. helpers.table_to_json({ tick=game.tick, seconds=WARM_SECONDS, speed=game.speed }))
  end
  if state.done or player.index ~= state.player_index then return end
  if state.phase == "warm" then
    game.tick_paused,game.speed=false,Config.warm_speed or 64
    local elapsed=game.tick-state.start_tick
    if elapsed>=(state.next_progress or 3600) then
      state.next_progress=elapsed+3600
      hide_other_screen_roots(player,state)
      log("MODDED GUI HISTORY "..helpers.table_to_json({elapsed_ticks=elapsed,
        coverage=Sampler.coverage(state.saved_surface or player.surface.index,PERIOD),controller_type=player.controller_type}))
    end
    if game.tick - state.start_tick < (WARM_SECONDS + 5) * 60 then return end
    game.speed = 1
    state.warm_ticks = game.tick - state.start_tick
    local surface = state.saved_surface and assert(game.surfaces[state.saved_surface]) or player.surface
    state.surface, state.surface_index = surface.name, surface.index
    state.coverage = Sampler.coverage(state.surface_index, PERIOD)
    assert(state.coverage >= PERIOD,
      "Reporter factory did not acquire the required real production-history coverage")
    local rates, recorded = Sampler.rates(state.surface_index, PERIOD)
    state.focus, state.recorded_seconds = choose_material(rates), recorded
    state.focus_rates_at_warmup = rates.nodes[state.focus]
    state.phase, state.next_tick = "open", game.tick + 1
    if Config.persist_warmed~=false then
      state.warmed_save="_autosave-production-flow-modded-warmed.zip"
      game.auto_save("production-flow-modded-warmed")
    end
    log("MODDED GUI WARMUP PASS " .. helpers.table_to_json({ warm_ticks=state.warm_ticks, coverage=state.coverage,
      focus=state.focus, surface=state.surface, focus_rates=state.focus_rates_at_warmup }))
    write(player, "warmup", { warm_ticks=state.warm_ticks, coverage=state.coverage, focus=state.focus,
      surface=state.surface, surface_index=state.surface_index, recorded_seconds=recorded,
      focus_rates=state.focus_rates_at_warmup, rate_source="actual Sampler.rates; no fixture override" })
    return
  end
  if game.tick < state.next_tick then return end
  local case = cases[state.step]
  if state.phase == 'camera-witness-prepare' then
    local camera = state.witness_camera
    local position = camera.position
    -- Full Sankey may be wider than the scroll viewport. Its camera center can
    -- be offscreen; use the freshly opened viewport's upper-left canvas area.
    local center={x=position.x-camera.style.minimal_width/64+100/32,
      y=position.y-camera.style.minimal_height/64+60/32}
    state.witness = rendering.draw_rectangle{surface=camera.surface_index,players={player.index},
      filled=true,color={r=1,g=0,b=1,a=1},
      left_top={center.x-.5,center.y-.5},right_bottom={center.x+.5,center.y+.5}}
    state.phase,state.next_tick='camera-witness-capture',game.tick+15
    return
  elseif state.phase == 'camera-witness-capture' then
    game.take_screenshot{player=player,path='modded-gui/'..case.name..'-camera-witness.png',
      resolution=RESOLUTION,show_gui=true,force_render=true}
    state.phase,state.next_tick='camera-witness-cleanup',game.tick+15
    return
  elseif state.phase == 'camera-witness-cleanup' then
    if state.witness.valid then state.witness.destroy() end
    state.witness,state.witness_camera=nil,nil
    state.step,state.phase,state.next_tick=state.step+1,'open',game.tick+15
    return
  end
  if not case then
    if Config.viewport then
      state.viewport = state.viewport or {}
      if viewport_step(UI, player, state) then return end
    end
    if not state.rate_card then
      open_case(UI, player, state, {tab="sankey", renderer="sprites"})
      local root = player.gui.screen.ssk_main
      local function material_bar(element, key)
        local tags = element.tags
        return tags.ssk_sk == "overview_jump" and (not key or tags.key == key) and valid_material(tags.key)
      end
      local target = find(root, function(e) return material_bar(e, state.focus) end)
        or assert(find(root, material_bar), "The factory must have a material bar to pin")
      local key = target.tags.key
      assert(UI.on_click{element=target, player_index=player.index})
      local panel = assert(find(root, function(e) return e.name == "ssk_selected_material" end))
      local card = panel.ssk_selected_scroll.ssk_rate_card_body
      assert(panel.tags.key == key and card.ssk_card_rates_plot and card.ssk_card_net_plot,
        "The pinned material must have both plots from recorded factory history")
      state.rate_card = {key=key, screenshot="sankey-rate-card.png"}
      state.next_tick = game.tick + 20
      return
    end
    game.take_screenshot{player=player,path="modded-gui/" .. state.rate_card.screenshot,
      resolution=RESOLUTION,show_gui=true,force_render=true}
    local actual_mods = {}
    for name, version in pairs(script.active_mods) do actual_mods[name] = version end
    local result = { cases=state.cases, coverage=state.coverage, saved_coverage=state.saved_coverage, warm_ticks=state.warm_ticks,
      focus=state.focus, surface=state.surface, surface_index=state.surface_index,
      actual_mods=actual_mods, display_scale=player.display_scale, display_resolution=player.display_resolution,
      resolution=RESOLUTION, engine_mouse_input=false, rate_source="actual Sampler.rates; no fixture override",
      focus_rates_at_warmup=state.focus_rates_at_warmup, suppressed_screen_roots=state.suppressed_screen_roots,
      speed_changes={ original=state.previous_speed, warmup=Config.warm_speed or 64, capture=1 }, failures=state.failures }
    result.forced_unpause=true
    result.controller_at_start=state.controller_at_start
    result.warmed_save=state.warmed_save
    result.viewport=state.viewport
    result.rate_card=state.rate_card
    write(player, "results", result)
    state.done = true
    assert(#state.failures == 0, "Reporter native GUI checks failed; see modded-gui/results.json")
    log("MODDED GUI NATIVE PASS " .. helpers.table_to_json({ cases=#state.cases, coverage=state.coverage,
      surface=state.surface, focus=state.focus, scale=player.display_scale }))
    return
  end
  if state.phase == "open" then
    open_case(UI, player, state, case)
    state.phase, state.next_tick = "capture", game.tick + 20
    return
  end
  hide_other_screen_roots(player, state)
  local root = assert(player.gui.screen.ssk_main, "Production Flow closed before native capture")
  root.bring_to_front()
  local canvas = assert(find(root, function(e) return e.name == "ssk_canvas" end), "Native chart canvas is missing")
  local profiler=helpers.create_profiler()
  local result = Check.inspect(canvas, player.display_scale)
  profiler.stop()
  result.inspect_profile=tostring(profiler)
  result.open_profile=state.open_profile
  local function check_geometry(sample)
    if not Config.viewport then return Check.assert_clear(sample) end
    -- The save's current surface can have a single isolated node or a chart
    -- zoom below the icon threshold. Check every target that is actually drawn.
    assert(sample.oversized_wrappers==0 and #sample.obstructions==0,"Chart interaction geometry is obstructed")
    assert(sample.ribbons==sample.hover_enabled,"Ribbon hover/leave events are not enabled")
    assert(#sample.label_alignment_errors==0,"Material label is displaced from its icon")
  end
  local ok, error_message = pcall(check_geometry, result)
  result.name, result.tab, result.renderer, result.passed = case.name, case.tab, case.renderer, ok
  result.tick, result.focus, result.surface = game.tick, state.focus, state.surface
  result.coverage, result.engine_mouse_input = Sampler.coverage(state.surface_index, PERIOD), false
  result.display_scale, result.display_resolution = player.display_scale, player.display_resolution
  result.controller_type,result.render_mode=player.controller_type,player.render_mode
  local camera=find(canvas,function(e)return e.type=="camera" end)
  result.actual_renderer=camera and "poly" or "sprites"
  if camera then
    result.camera={surface_index=camera.surface_index,position=camera.position,zoom=camera.zoom,
      width=camera.style.minimal_width,height=camera.style.minimal_height,
      witness_layout_position={x=100,y=60}}
    local objects=storage.canvas and storage.canvas[player.index] and storage.canvas[player.index].objs or {}
    local valid=0
    for _,object in ipairs(objects) do if object.valid then valid=valid+1 end end
    result.render_objects={count=#objects,valid=valid}
    assert(valid>0 and valid==#objects,'Polygon chart lost its native rendering objects')
    local surface=game.get_surface(Canvas.SURFACE)
    if surface then
      result.canvas_surface={index=surface.index,hidden=player.force.get_surface_hidden(surface),chunks={}}
      local p,w,h=camera.position,camera.style.minimal_width,camera.style.minimal_height
      for x=math.floor((p.x-w/64)/32),math.floor((p.x+w/64)/32) do
        for y=math.floor((p.y-h/64)/32),math.floor((p.y+h/64)/32) do
          local chunk={x=x,y=y}
          result.canvas_surface.chunks[#result.canvas_surface.chunks+1]={x=x,y=y,
            generated=surface.is_chunk_generated(chunk),charted=player.force.is_chunk_charted(surface,chunk)}
        end
      end
    end
  end
  if not ok then
    result.error = tostring(error_message)
    state.failures[#state.failures + 1] = { name=case.name, error=result.error }
  end
  write(player, case.name, result)
  game.take_screenshot { player=player, path="modded-gui/" .. case.name .. ".png",
    resolution=RESOLUTION, show_gui=true, force_render=true }
  state.cases[#state.cases + 1] = result
  log("MODDED GUI CASE " .. helpers.table_to_json({ name=case.name, passed=ok, icons=result.icons,
    obstructions=#result.obstructions, coverage=result.coverage }))
  if camera then
    state.witness_camera=camera
    state.phase,state.next_tick='camera-witness-prepare',game.tick+15
  else
    state.step, state.phase, state.next_tick = state.step + 1, "open", game.tick + 30
  end
end

return T
