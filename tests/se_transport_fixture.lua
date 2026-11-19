-- Independent public-event observer. The private SE adapter is used only for
-- fixture construction and ground truth, never as a shipping integration API.
local function emit(kind, data)
  log("SE FIXTURE " .. kind .. " " .. helpers.table_to_json(data))
end
local function describe(e)
  if not (e and e.valid) then return nil end
  return {name=e.name, unit=e.unit_number, surface=e.surface.name, surface_index=e.surface.index, force=e.force.name}
end
script.on_event(defines.events.on_script_trigger_effect,function(e)
  if e.effect_id=="production-flow-se-cannon-dispatch" then
    storage.cannon_markers=storage.cannon_markers or {}
    storage.cannon_markers[#storage.cannon_markers+1]={tick=e.tick,surface=e.surface_index}
    emit("CANNON_MARKER",{tick=e.tick,surface=e.surface_index,source=describe(e.source_entity),target=describe(e.target_entity),
      source_position=e.source_position,target_position=e.target_position,quality=e.quality})
  end
end)
local function record(name, event)
  local r = {event=name, tick=event.tick, unit=event.unit_number, source=describe(event.launchpad),
    from_zone=event.zone_name,from_zone_index=event.zone_index,to_zone=event.destination_zone_name,to_zone_index=event.destination_zone_index,landing_pad=describe(event.landing_pad),
    manifest=event.launched_contents}
  local pod = event.cargo_pod
  if pod and pod.valid then
    r.pod=describe(pod)
    local inv=pod.get_inventory(defines.inventory.cargo_unit)
    r.manifest=inv and inv.get_contents()
  end
  storage.observed[#storage.observed+1] = r
  emit("PUBLIC", r)
end
for _, name in ipairs({"se_on_cargo_rocket_launched", "se_on_cargo_rocket_padless",
  "on_cargo_pod_finished_ascending", "on_cargo_pod_finished_descending", "on_cargo_pod_delivered_cargo"}) do
  if defines.events[name] then script.on_event(defines.events[name], function(e) record(name,e) end) end
end
script.on_event(defines.events.on_entity_cloned,function(e)
  if e.source and e.source.valid and (e.source.name=="se-spaceship-console" or e.source.name=="steel-chest" or e.source.name=="storage-tank") then
    local r={event="on_entity_cloned",tick=e.tick,source=describe(e.source),destination=describe(e.destination)}
    if e.destination.type=="container" then r.manifest=e.destination.get_inventory(defines.inventory.chest).get_contents() end
    if e.destination.type=="storage-tank" then r.fluids=e.destination.get_fluid_contents() end
    storage.observed[#storage.observed+1]=r;emit("PUBLIC",r)
  end
end)
script.on_init(function()
  if remote.interfaces.freeplay and remote.interfaces.freeplay.set_skip_intro then
    remote.call("freeplay","set_skip_intro",true)
  end
  storage.observed={};storage.cannon_markers={}
  storage.start=game.tick
  storage.fixture=remote.call("production-flow-se-fixture", "build")
  emit("READY", storage.fixture)
end)
script.on_event(defines.events.on_tick, function(e)
  if storage.finished then return end
  game.speed=16
  local t=e.tick-storage.start
  for _,launch in ipairs(storage.fixture.launch_schedule) do
    if t==launch.tick then remote.call("production-flow-se-fixture","launch",launch.name) end
  end
  for _,shot in ipairs(storage.fixture.cannon_schedule) do
    if t==shot.tick then remote.call("production-flow-se-fixture","fire",shot.name,shot.miss) end
  end
  if t==900 then remote.call("production-flow-se-fixture", "ship_launch") end
  if t==1200 then remote.call("production-flow-se-fixture", "ship_anchor") end
  if t==1320 then remote.call("production-flow-se-fixture", "ship_unload") end
  if t==storage.fixture.checkpoint_tick and not storage.checkpoint then
    storage.checkpoint=true
    emit("CHECKPOINT", remote.call("production-flow-se-fixture", "checkpoint"))
    game.auto_save("se-fixture-inflight")
  end
  if t>0 and t%600==0 then remote.call("production-flow-se-fixture","sample") end
  if t==storage.fixture.finish_tick and not storage.finished then
    storage.finished=true
    local result=remote.call("production-flow-se-fixture", "verify")
    local launches=0
    for _, r in ipairs(storage.observed) do if r.event=="se_on_cargo_rocket_launched" then launches=launches+1 end end
    assert(launches==storage.fixture.counts.rockets,"Public rocket launch count mismatch: "..launches)
    assert(#storage.cannon_markers==storage.fixture.counts.cannon_shots,"Public cannon firing marker count mismatch")
    local function keyed(stacks)
      local values={}
      for _,s in pairs(stacks) do
        local quality=s.quality
        if quality and type(quality)~="string" then quality=quality.name end
        local key=s.name.."/"..(quality or "normal")
        values[key]=(values[key] or 0)+s.count
      end
      return values
    end
    local ship_chests,ship_tanks=0,0
    local named_padless=assert(storage.fixture.scenarios.padless)
    local saw_named_padless=false
    for _,r in ipairs(storage.observed) do
      if r.event=="se_on_cargo_rocket_launched" then
        local expected=keyed(assert(storage.fixture.expected[r.unit]))
        local actual=keyed(r.manifest)
        for k,v in pairs(expected) do assert(actual[k]==v,"Public launch manifest mismatch: "..k) end
        for k,v in pairs(actual) do assert(expected[k]==v,"Unexpected launch cargo: "..k) end
      elseif r.event=="se_on_cargo_rocket_padless" and r.unit==named_padless.unit then
        assert(r.to_zone_index==named_padless.to_zone,"Named padless callback changed destination")
        saw_named_padless=true
      elseif r.event=="on_entity_cloned" and r.manifest then
        assert(keyed(r.manifest)["electronic-circuit/normal"]==100,"Public ship manifest mismatch")
        ship_chests=ship_chests+1
      elseif r.event=="on_entity_cloned" and r.fluids then
        assert(r.fluids.water==1000,"Public ship fluid snapshot mismatch")
        ship_tanks=ship_tanks+1
      end
    end
    assert(saw_named_padless,"Missing genuine public padless callback for named fixture rocket")
    assert(ship_chests==2 and ship_tanks==2,"Missing public ship launch/anchor clone snapshots")
    result.observed=storage.observed
    result.public_counts={rockets=launches,cannon_markers=#storage.cannon_markers}
    result.production=remote.call("production-flow-se-verification","check",storage.fixture)
    helpers.write_file("se-fixture-results.json", helpers.table_to_json(result), false)
    emit("PASS", result)
    game.speed=1
    game.auto_save("se-fixture-complete")
  end
end)
