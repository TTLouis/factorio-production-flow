-- Test-only control script. Subscribe to native pod events without importing or
-- dispatching Production Flow callbacks. No synthetic delivery is recorded.
local Config = require("cargo_empty_witness_config")
local CASES = Config.product_check and { "cargo", "empty" } or { "cargo", "empty", "player-only" }
local function write(name, value, append)
  helpers.write_file("cargo-empty/" .. name, helpers.table_to_json(value) .. "\n", append, 1)
end
local function passenger(pod)
  local rider = pod.get_passenger()
  return rider and rider.valid and rider.object_name or false
end
local function count(pod)
  local inventory = pod.get_inventory(defines.inventory.cargo_unit)
  if not (inventory and inventory.valid) then return nil end
  local total = 0
  for _, item in pairs(inventory.get_contents()) do total = total + item.count end
  return total
end
local function observe(event)
  local pod = event.cargo_pod
  if not (pod and pod.valid) then return end
  local s = storage.cargo_empty_witness
  local case = s and s.by_unit[pod.unit_number]
  if not case then return end
  local names = {
    [defines.events.on_cargo_pod_started_ascending]="started_ascending",
    [defines.events.on_cargo_pod_finished_ascending]="finished_ascending",
    [defines.events.on_cargo_pod_finished_descending]="finished_descending",
    [defines.events.on_cargo_pod_delivered_cargo]="delivered_cargo",
  }
  local name = assert(names[event.name])
  case.events[name] = (case.events[name] or 0) + 1
  case.last_event_tick = event.tick
  if name == "finished_descending" then case.landed_tick = event.tick end
  local row = { case=case.name, event=name, tick=event.tick, unit=pod.unit_number,
    pod_state=pod.cargo_pod_state, inventory_count=count(pod), passenger=passenger(pod), player_index=event.player_index,
    spawned_container=event.spawned_container and event.spawned_container.valid or false }
  write("events.jsonl", row, true)
  log("CARGO EMPTY EVENT " .. helpers.table_to_json(row))
end
for _, name in ipairs({ "on_cargo_pod_started_ascending", "on_cargo_pod_finished_ascending",
  "on_cargo_pod_finished_descending", "on_cargo_pod_delivered_cargo" }) do
  script.on_event(defines.events[name], observe)
end
script.on_init(function()
  if remote.interfaces.freeplay and remote.interfaces.freeplay.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
  game.tick_paused = false
end)
local function launch(s, player, name)
  local case = { name=name, start_tick=game.tick, events={} }
  s.cases[#s.cases + 1] = case
  local ok, message = pcall(function()
    if name == "player-only" then
      assert(player.character, "Normal client did not create a character")
      assert(player.enter_space_platform(s.platform), "Public enter_space_platform rejected the test player")
    end
    local pod = assert(s.hub.create_cargo_pod(), "Native hub hatch did not create a pod")
    case.unit, case.pod = pod.unit_number, pod
    s.by_unit[pod.unit_number] = case
    if name == "cargo" then assert(pod.get_inventory(defines.inventory.cargo_unit).insert{name="iron-plate",count=1} == 1) end
    if name == "player-only" then
      pod.set_passenger(player)
      assert(pod.get_passenger(), "Native cargo pod did not retain the passenger")
    end
    case.initial_count, case.initial_passenger = assert(count(pod), "Pod has no cargo inventory"), passenger(pod)
    local position = assert(s.ground.find_non_colliding_position("cargo-pod-container", {x=30*s.step,y=0}, 40, 1))
    pod.cargo_pod_destination = {type=defines.cargo_destination.surface,surface=s.ground,
      position=position,land_at_exact_position=true}
    case.launched = true
  end)
  if not ok then case.blocker=tostring(message);case.finished=true end
  write(name .. "-launch.json", {name=name,unit=case.unit,start_tick=case.start_tick,
    initial_count=case.initial_count,initial_passenger=case.initial_passenger,launched=case.launched or false,blocker=case.blocker})
  s.current = case
end
script.on_event(defines.events.on_tick, function()
  local player = game.get_player(1)
  if not (player and player.connected) then return end
  local s = storage.cargo_empty_witness
  if not s then
    local platform = assert(player.force.create_space_platform{name="Empty Cargo Witness",planet="nauvis",starter_pack="space-platform-starter-pack"})
    local hub = assert(platform.apply_starter_pack(true))
    platform.space_location = "nauvis"
    s = {platform=platform,hub=hub,ground=game.surfaces.nauvis,step=1,cases={},by_unit={},next_tick=game.tick+30}
    storage.cargo_empty_witness = s
    game.tick_paused, game.speed = false, 16
  end
  if s.done or game.tick < s.next_tick then return end
  local current = s.current
  if current then
    if current.landed_tick and game.tick >= current.landed_tick + 120 then current.finished = true end
    if game.tick - current.start_tick >= 3600 then current.blocker=current.blocker or "No native landing within 3,600 ticks";current.finished=true end
    if not current.finished then return end
    if Config.product_check then
      local summary=remote.call("cargo_empty_witness_product", "summary")
      current.product_summary=summary
      write(current.name .. "-product.json",summary,false)
      assert(summary.receipt_gaps==0 and summary.pending_nonempty==0 and summary.pending_empty_unfinished==0,
        "Native empty delivery created a receipt gap or leaked unfinished cargo")
      assert(summary.pending==summary.empty_delivered_markers and summary.empty_delivered_markers<=(current.name=="empty" and 1 or 0),
        "Only the bounded confirmed-empty replay marker may occupy a completed pending slot")
      assert(summary.received==1 and summary.received_iron_plate==1,"Positive cargo receipt was lost or an empty arrival was invented")
    end
    s.current, s.step, s.next_tick = nil, s.step + 1, game.tick + 120
    return
  end
  if CASES[s.step] then launch(s,player,CASES[s.step]);return end
  local results = {}
  for _, case in ipairs(s.cases) do
    results[#results + 1] = {name=case.name,unit=case.unit,initial_count=case.initial_count,
      initial_passenger=case.initial_passenger,launched=case.launched or false,events=case.events,blocker=case.blocker,
      landed=case.landed_tick~=nil,delivered_event_fired=(case.events.delivered_cargo or 0)>0,product_summary=case.product_summary}
  end
  local cargo, rider = results[1], results[3]
  local rider_verified = cargo and cargo.delivered_event_fired and rider and rider.initial_count==0
    and rider.initial_passenger~=false and rider.landed
  local empty=results[2]
  local product_verified=Config.product_check and cargo and cargo.delivered_event_fired and empty and empty.initial_count==0
    and empty.delivered_event_fired and empty.product_summary and empty.product_summary.receipt_gaps==0
    and empty.product_summary.received==1 and empty.product_summary.received_iron_plate==1
  local verified=Config.product_check and product_verified or rider_verified
  local actual_mods={};for name,version in pairs(script.active_mods) do actual_mods[name]=version end
  local result = {engine=script.active_mods.base,cases=results,player_only_native_transport_verified=not not rider_verified,
    product_checks_passed=not not product_verified,
    engine_events_only=true,direct_handler_dispatch=false,animation_shortcuts=false,actual_mods=actual_mods}
  write("results.json",result,false)
  s.done=true;game.speed=1
  assert(verified,"Cargo witness blocked or positive control failed; see cargo-empty/results.json")
  log("CARGO EMPTY NATIVE WITNESS PASS " .. helpers.table_to_json(result))
end)
