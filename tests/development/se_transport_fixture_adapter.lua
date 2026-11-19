-- Injected only into a disposable SE copy. This is private instrumentation.
local CANNON_MISS={x=32,y=32}

local function catcher_at(surface,position)
  return surface.find_entities_filtered{name="se-delivery-cannon-chest",position=position,limit=1}[1]
end

local function emit(kind, data)
  log("SE FIXTURE TRUTH " .. kind .. " " .. helpers.table_to_json(data))
end
local function contents(entity, id)
  if not (entity and entity.valid) then return {} end
  local inv=entity.get_inventory(id)
  return inv and inv.get_contents() or {}
end
local function amount(stacks, name)
  local count=0
  for _, s in pairs(stacks) do if s.name==name then count=count+s.count end end
  return count
end
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
-- Every number below is read from live inventories/statistics. These private
-- probes never call statistics.on_flow and never populate Production Flow bins.
local function watched_items()
  local f=storage.pf_fixture;local names={}
  for name in pairs(f.stat_items or {}) do names[#names+1]=name end
  table.sort(names);return names
end
local function statistics(surface)
  local stats=game.forces.player.get_item_production_statistics(surface)
  local made,used=stats.input_counts,stats.output_counts
  local result={}
  for _,name in ipairs(watched_items()) do result[name]={made=made[name] or 0,used=used[name] or 0} end
  return result
end
local function physical(surface)
  local old,stored={},{}
  -- LuaInventory wrappers returned through different IDs need not compare
  -- equal. Read exactly the same one main inventory/type as ChestStock.
  local inventory={container="chest",["logistic-container"]="chest",["temporary-container"]="chest",["cargo-landing-pad"]="cargo_landing_pad_main",
    ["space-platform-hub"]="hub_main",["rocket-silo"]="rocket_silo_attached_cargo_unit"}
  for _,entity in pairs(surface.find_entities_filtered{force=game.forces.player,
    type={"container","logistic-container","temporary-container","cargo-landing-pad","space-platform-hub","rocket-silo"}}) do
    local inv=entity.get_inventory(defines.inventory[inventory[entity.type]])
    if inv and inv.valid then
      for _,stack in pairs(inv.get_contents()) do
        stored[stack.name]=(stored[stack.name] or 0)+stack.count
        if entity.type=="container" or entity.type=="logistic-container" then old[stack.name]=(old[stack.name] or 0)+stack.count end
      end
    end
  end
  return stored,old
end
local function numeric_delta(after,before)
  local result={};for _,name in ipairs(watched_items()) do result[name]=(after[name] or 0)-(before[name] or 0) end;return result
end
local function begin_boundary(kind,surfaces,details)
  local b={kind=kind,tick=game.tick,details=details or {},surfaces={},stats_before={},physical_before={},physical_chests_before={}}
  local seen={}
  for _,surface in ipairs(surfaces) do if not seen[surface.index] then
    seen[surface.index]=true;b.surfaces[#b.surfaces+1]=surface.name
    b.stats_before[surface.name]=statistics(surface)
    b.physical_before[surface.name],b.physical_chests_before[surface.name]=physical(surface)
  end end
  return b
end
local function end_boundary(b)
  assert(game.tick==b.tick,"Atomic statistics probe advanced a simulation tick")
  b.stats_after={};b.stats_delta={};b.physical_after={};b.physical_delta={};b.physical_chests_after={};b.physical_chests_delta={}
  for _,name in ipairs(b.surfaces) do
    local surface=game.surfaces[name];local after=statistics(surface)
    b.stats_after[name]=after;b.stats_delta[name]={}
    for material,value in pairs(after) do local before=b.stats_before[name][material]
      b.stats_delta[name][material]={made=value.made-before.made,used=value.used-before.used}
    end
    b.physical_after[name],b.physical_chests_after[name]=physical(surface)
    b.physical_delta[name]=numeric_delta(b.physical_after[name],b.physical_before[name])
    b.physical_chests_delta[name]=numeric_delta(b.physical_chests_after[name],b.physical_chests_before[name])
  end
  storage.pf_fixture.stat_deltas[#storage.pf_fixture.stat_deltas+1]=b
  emit("BOUNDARY_STATS",b)
end
local function factory_diagnostics()
  local f=storage.pf_fixture;local state={tick=game.tick,machines={},chests={},inserters={}}
  local function target(entity) return entity and entity.valid and {unit=entity.unit_number,name=entity.name,type=entity.type} or nil end
  local function status(entity)
    for name,id in pairs(defines.entity_status) do if entity.status==id then return name end end
    return tostring(entity.status)
  end
  for name,entity in pairs(f.factory.machines) do
    local recipe=entity.get_recipe()
    local input=entity.type=="furnace" and defines.inventory.furnace_source or defines.inventory.crafter_input
    local output=entity.type=="furnace" and defines.inventory.furnace_result or defines.inventory.crafter_output
    state.machines[name]={unit=entity.unit_number,products_finished=entity.products_finished,recipe=recipe and recipe.name,
      energy=entity.energy,status=status(entity),active=entity.active,input=contents(entity,input),output=contents(entity,output),
      recipe_enabled=recipe and game.forces.player.recipes[recipe.name].enabled,electric_network=entity.electric_network_id}
  end
  for name,entity in pairs(f.factory.chests) do state.chests[name]=contents(entity,defines.inventory.chest) end
  for _,entity in ipairs(f.factory.inserters or {}) do
    local held=entity.held_stack
    state.inserters[#state.inserters+1]={unit=entity.unit_number,position=entity.position,status=status(entity),energy=entity.energy,
      pickup=entity.pickup_position,drop=entity.drop_position,pickup_target=target(entity.pickup_target),drop_target=target(entity.drop_target),
      held=held.valid_for_read and {name=held.name,count=held.count} or nil,electric_network=entity.electric_network_id}
  end
  return state
end
local function factory_sample()
  local f=storage.pf_fixture;local previous=f.samples[#f.samples]
  if previous and previous.tick==game.tick then return {tick=previous.tick,samples=#f.samples,duplicate_skipped=true} end
  local sample=factory_diagnostics();sample.surfaces={}
  for _,id in ipairs(f.zones) do
    local surface=Zone.get_surface(Zone.from_zone_index(id));local stored,chests=physical(surface)
    sample.surfaces[surface.name]={statistics=statistics(surface),physical_storage=stored,physical_chests=chests}
  end
  f.samples[#f.samples+1]=sample
  return {tick=sample.tick,samples=#f.samples}
end
local function build_factory(surface,make)
  local f=storage.pf_fixture
  local factory={machines={},chests={},inserters={},descriptor={surface=surface.name,area={{-94,38},{-12,90}},
    provenance="Live engine crafting, inserters and belts; initial feeds seeded once; fixture recipes unlocked with runtime ingredients unchanged; no fabricated samples or statistics",
    power={prototype="electric-energy-interface",public_api_power_production=100000000},machines={},chests={},belts=0,inserters=0}}
  f.factory=factory
  local function entity(name,x,y,direction) return make(surface,name,x+.5,y+.5,direction) end
  local function chest(role,x,y,stacks)
    local e=entity("steel-chest",x,y);factory.chests[role]=e
    local inserted={}
    for _,stack in ipairs(stacks or {}) do assert(e.insert(stack)==stack.count,"Factory seed capacity: "..role);inserted[#inserted+1]=stack end
    factory.descriptor.chests[#factory.descriptor.chests+1]={role=role,unit=e.unit_number,position=e.position,initial=inserted}
    return e
  end
  local function machine(role,name,x,y,recipe)
    local e=entity(name,x,y)
    if name~="electric-furnace" then
      -- Basic cable/circuit recipes are technology locked in Factorio 2.1.
      -- Unlock this fixture's real recipe; do not change its ingredients.
      game.forces.player.recipes[recipe].enabled=true
      e.set_recipe(recipe)
      local assigned=e.get_recipe();assert(assigned and assigned.name==recipe,"Factory recipe rejected: "..recipe)
    end
    factory.machines[role]=e
    factory.descriptor.machines[#factory.descriptor.machines+1]={role=role,name=name,unit=e.unit_number,position=e.position,recipe=recipe,ingredients=prototypes.recipe[recipe].ingredients}
    return e
  end
  local function inserter(x,y,direction)
    -- Vanilla inserter prototype vectors point pickup north/drop south at
    -- direction=north; the argument here describes material-flow direction.
    local opposite={[defines.direction.east]=defines.direction.west,[defines.direction.west]=defines.direction.east,
      [defines.direction.south]=defines.direction.north,[defines.direction.north]=defines.direction.south}
    local e=entity("fast-inserter",x,y,opposite[direction]);e.inserter_stack_size_override=1
    local pickup,drop=e.pickup_position,e.drop_position
    local dx=direction==defines.direction.east and 1 or direction==defines.direction.west and -1 or 0
    local dy=direction==defines.direction.south and 1 or direction==defines.direction.north and -1 or 0
    assert((drop.x-pickup.x)*dx+(drop.y-pickup.y)*dy>0,"Factory inserter flow reversed")
    factory.inserters[#factory.inserters+1]=e
    factory.descriptor.inserters=factory.descriptor.inserters+1
    factory.descriptor.inserter_layout=factory.descriptor.inserter_layout or {}
    factory.descriptor.inserter_layout[#factory.descriptor.inserter_layout+1]={unit=e.unit_number,position=e.position,pickup=pickup,drop=drop}
    return e
  end
  for i,x in ipairs({-80,-60,-40,-20}) do
    machine("iron-smelter-"..i,"electric-furnace",x,52,"iron-plate")
    chest("iron-ore-feed-"..i,x-3,52,{{name="iron-ore",count=2000}})
    chest("iron-plate-stock-"..i,x+3,52,i<=2 and {{name="iron-plate",count=200}} or nil)
    inserter(x-2,52,defines.direction.east);inserter(x+2,52,defines.direction.east)
  end
  machine("gear-assembler","assembling-machine-2",-77,55,"iron-gear-wheel")
  inserter(-77,53,defines.direction.south);inserter(-77,57,defines.direction.south)
  chest("gear-output",-77,58)
  -- A real belt carries smelted plates into a tracked stock chest.
  inserter(-57,53,defines.direction.south)
  for y=54,64 do entity("transport-belt",-57,y,defines.direction.south);factory.descriptor.belts=factory.descriptor.belts+1 end
  inserter(-57,65,defines.direction.south);chest("smelted-iron-belt-stock",-57,66)
  machine("circuit-assembler","assembling-machine-2",-57,69,"electronic-circuit")
  inserter(-57,71,defines.direction.south);chest("circuit-output",-57,72)
  machine("cable-assembler","assembling-machine-2",-63,69,"copper-cable")
  chest("copper-plate-feed",-63,66,{{name="copper-plate",count=4000}})
  inserter(-63,67,defines.direction.south);inserter(-61,69,defines.direction.east)
  chest("cable-stock",-60,69);inserter(-59,69,defines.direction.east)
  -- AAI Industry's real circuit recipe uses stone tablets, not iron plates.
  local substrate=false
  for _,ingredient in pairs(prototypes.recipe["electronic-circuit"].ingredients) do if ingredient.name=="stone-tablet" then substrate=true end end
  assert(substrate,"Pinned AAI/SE circuit recipe no longer uses stone tablets")
  chest("circuit-tablet-feed",-54,69)
  inserter(-55,69,defines.direction.west)
  machine("tablet-assembler","assembling-machine-2",-54,72,"stone-tablet")
  chest("stone-brick-feed",-54,75,{{name="stone-brick",count=2000}})
  inserter(-54,74,defines.direction.north);inserter(-54,70,defines.direction.north)
  for _,x in ipairs({-86,-68,-50,-32,-14}) do for _,y in ipairs({44,62,80}) do make(surface,"substation",x,y) end end
  local power=make(surface,"electric-energy-interface",-89,41)
  power.electric_buffer_size=1000000000;power.energy=1000000000;power.power_production=100000000;power.power_usage=0
  factory.descriptor.power.unit=power.unit_number;factory.descriptor.power.position=power.position
  game.forces.player.chart(surface,{{-96,36},{-10,94}})
end
local function export_measurements()
  local f=storage.pf_fixture
  local data={provenance={source="Live Factorio SE fixture",sample_interval_ticks=600,statistics="LuaForce.get_item_production_statistics input_counts/output_counts",
    physical_basis="physical-storage-v2",legacy_basis="physical-chests-v1",qualities="all",no_statistics_or_history_injection=true},
    factory=f.factory.descriptor,samples=f.samples,stat_deltas=f.stat_deltas}
  helpers.write_file("se-fixture-measurements.json",helpers.table_to_json(data),false)
  local rows={"tick\tsurface\titem\tmade_cumulative\tused_cumulative\tphysical_storage\tphysical_chests"}
  for _,sample in ipairs(f.samples) do for name,scope in pairs(sample.surfaces) do for _,item in ipairs(watched_items()) do
    local flow=scope.statistics[item]
    rows[#rows+1]=table.concat({sample.tick,name,item,flow.made,flow.used,scope.physical_storage[item] or 0,scope.physical_chests[item] or 0},"\t")
  end end end
  helpers.write_file("se-fixture-measurements.tsv",table.concat(rows,"\n").."\n",false)
  local boundary_rows={"tick\tkind\tsurface\titem\tmade_delta\tused_delta\tphysical_storage_delta\tphysical_chests_delta"}
  for _,boundary in ipairs(f.stat_deltas) do for _,scope in ipairs(boundary.surfaces) do for _,item in ipairs(watched_items()) do
    local flow=boundary.stats_delta[scope][item]
    boundary_rows[#boundary_rows+1]=table.concat({boundary.tick,boundary.kind,scope,item,flow.made,flow.used,
      boundary.physical_delta[scope][item],boundary.physical_chests_delta[scope][item]},"\t")
  end end end
  helpers.write_file("se-fixture-boundary-deltas.tsv",table.concat(boundary_rows,"\n").."\n",false)
  return data
end
-- Input contract for the disposable scenario, distinct from actual receipts.
local function metadata()
  local f=storage.pf_fixture
  local result={contract_version=2,from=Zone.get_surface(Zone.from_zone_index(f.origin)).name,to=Zone.get_surface(Zone.from_zone_index(f.destination)).name,
    rockets=f.rockets,expected=f.expected,launch_schedule=f.launch_schedule,cannon_schedule=f.cannon_schedule,
    checkpoint_tick=1500,finish_tick=33000,cannon=f.cannon.unit_number,receiver=f.receiver.unit_number,
    cannon_payload_count=f.cannon_amount,cannon_preparation="One prepared package inserted before each real firing; packaging is not part of this fixture",surfaces={},by_surface={},receivers={},scenarios=f.scenarios,
    counts={rockets=#f.launch_schedule,cannon_shots=#f.cannon_schedule,cannon_senders=count(f.cannons),surfaces=#f.zones},factory=f.factory and f.factory.descriptor}
  for _,id in ipairs(f.zones) do
    local zone=Zone.from_zone_index(id);local surface=Zone.get_surface(zone)
    result.surfaces[#result.surfaces+1]={zone=id,name=zone.name,surface_index=surface.index,type=zone.type}
    result.by_surface[surface.name]={shipments=0,imports=0,exports=0,cannon_effects=0,cannon_senders=0,cannon_receivers=0,sent={},import_sources={},export_destinations={}}
  end
  for _,scenario in pairs(f.scenarios) do
    for _,side in ipairs({"from","to"}) do
      local entry=result.by_surface[scenario[side]]
      entry.shipments=entry.shipments+1
      local direction=side=="from" and "exports" or "imports";entry[direction]=entry[direction]+1
      if side=="from" then entry.export_destinations[scenario.to]=true else entry.import_sources[scenario.from]=true end
      for _,stack in pairs(f.expected[scenario.unit]) do entry.sent[stack.name]=(entry.sent[stack.name] or 0)+stack.count end
    end
  end
  for _,entity in pairs(f.cannons) do result.by_surface[entity.surface.name].cannon_senders=result.by_surface[entity.surface.name].cannon_senders+1 end
  for name,entity in pairs(f.receivers) do
    local expected=0
    for _,shot in ipairs(f.cannon_schedule) do if not shot.miss and f.cannon_targets[shot.name].receiver==name then expected=expected+f.cannon_amount end end
    result.receivers[#result.receivers+1]={unit=entity.unit_number,surface=entity.surface.name,name=name,item="iron-plate",count=expected}
    result.by_surface[entity.surface.name].cannon_receivers=result.by_surface[entity.surface.name].cannon_receivers+1
  end
  for _,shot in ipairs(f.cannon_schedule) do
    local surface=f.cannons[shot.name].surface.name
    result.by_surface[surface].cannon_effects=result.by_surface[surface].cannon_effects+1
  end
  for _,entry in pairs(result.by_surface) do entry.import_routes=count(entry.import_sources);entry.export_routes=count(entry.export_destinations) end
  return result
end
local function ship_manifest()
  local f=storage.pf_fixture
  local ship=f.ship and Spaceship.from_index(f.ship)
  if not ship or not ship.console.valid then return nil end
  local items,fluids,fuel={},{},{}
  for _,e in pairs(ship.console.surface.find_entities_filtered{area=ship.known_bounds,type={"container","storage-tank"}}) do
    local p=util.position_to_tile(e.position)
    if ship.known_tiles[p.x] and ship.known_tiles[p.x][p.y]=="floor_console_connected" then
      if e.type=="container" then
        for _,s in pairs(contents(e,defines.inventory.chest)) do items[s.name]=(items[s.name] or 0)+s.count end
      else
        local target=util.table_contains(Spaceship.names_booster_tanks,e.name) and fuel or fluids
        for name,n in pairs(e.get_fluid_contents()) do target[name]=(target[name] or 0)+n end
      end
    end
  end
  return {ship=ship.index,name=ship.name,surface=ship.console.surface.name,console=ship.console.unit_number,items=items,fluids=fluids,fuel=fuel}
end
local function snapshot()
  local f=storage.pf_fixture
  local pads={}
  for name,p in pairs(f.pads) do pads[name]=contents(p,defines.inventory.cargo_landing_pad_main) end
  local rockets={}
  for name,unit in pairs(f.rockets) do
    local r=Launchpad.from_unit_number(unit)
    rockets[name]={status=r.launch_status,manifest=r.launched_contents,inventory=contents(r.container,defines.inventory.chest),rocket_present=r.silo.rocket~=nil}
  end
  return {tick=game.tick,pads=pads,rockets=rockets,receiver=contents(f.receiver,defines.inventory.chest),
    cannon_payloads=count(storage.delivery_cannon_payloads),truth=f.truth,ship=ship_manifest(),factory_diagnostics=f.factory and factory_diagnostics()}
end
for _,name in ipairs({"on_spaceship_launched","on_spaceship_anchored"}) do
  Event.addListener(name,function(e)
    if storage.pf_fixture and storage.pf_fixture.ship==e.spaceship_index then
      local r={kind=name,tick=game.tick,manifest=ship_manifest()}
      table.insert(storage.pf_fixture.truth,r);emit("SHIP",r)
    end
  end,true)
end
local original_land=Launchpad.tick_journey_land
Launchpad.tick_journey_land=function(task)
  local pad=task.launching_to_destination.landing_pad
  local r={kind="rocket_land",tick=game.tick,unit=task.struct and task.struct.unit_number,
    destination=task.launching_to_destination.zone.name,had_pad=pad and pad.valid or false,
    surviving_manifest=task.launched_inventory and task.launched_inventory.valid and task.launched_inventory.get_contents() or {},
    before=pad and contents(pad.container,defines.inventory.cargo_landing_pad_main) or {}}
  local surface=Zone.get_make_surface(task.launching_to_destination.zone)
  local boundary=storage.pf_fixture and begin_boundary("rocket_arrival",{surface},{unit=r.unit,destination=r.destination,had_pad=r.had_pad,surviving_manifest=r.surviving_manifest})
  if boundary then boundary.endpoint_before=r.before end
  original_land(task)
  r.after=pad and contents(pad.container,defines.inventory.cargo_landing_pad_main) or {}
  if boundary then boundary.endpoint_after=r.after;end_boundary(boundary) end
  if storage.pf_fixture then table.insert(storage.pf_fixture.truth,r);emit("ROCKET_LAND",r) end
end
local original_payload=DeliveryCannon.do_payload_effect
DeliveryCannon.do_payload_effect=function(payload)
  local r={kind="cannon_land",tick=game.tick,target=payload.target_zone.name,position=payload.target_position,
    item=payload.stack.name,count=payload.stack.count,quality=payload.stack.quality.name}
  local surface=Zone.get_make_surface(payload.target_zone)
  local receiver=catcher_at(surface,payload.target_position)
  r.receiver=receiver and receiver.unit_number
  local boundary=storage.pf_fixture and begin_boundary("cannon_arrival",{surface},{item=r.item,count=r.count,quality=r.quality,target=r.target,receiver=r.receiver})
  if boundary then boundary.endpoint_before=contents(receiver,defines.inventory.chest) end
  original_payload(payload)
  if boundary then
    boundary.endpoint_after=contents(receiver,defines.inventory.chest)
    r.caught=amount(boundary.endpoint_after,r.item)-amount(boundary.endpoint_before,r.item)
    end_boundary(boundary)
  end
  if storage.pf_fixture then table.insert(storage.pf_fixture.truth,r);emit("CANNON_LAND",r) end
end
remote.add_interface("production-flow-se-fixture", {
  build=function()
    assert(not storage.pf_fixture)
    local origin=Zone.from_name("Nauvis")
    local destination=origin.orbit
    local moons={}
    for _,zone in pairs(origin.children or {}) do if zone.type=="moon" then moons[#moons+1]=zone end end
    table.sort(moons,function(left,right) return left.index<right.index end)
    local moon=assert(moons[1],"Nauvis fixture requires its generated moon")
    local moon_orbit=assert(moon.orbit,"Nauvis moon has no orbit")
    setup_force(game.forces.player)
    storage.forces.player.has_players=true -- --create has no player yet.
    storage.forces.player.satellites_launched=2 -- Unlock SE remote targeting.
    local a=Zone.get_make_surface(origin)
    local b=Zone.get_make_surface(destination)
    local c=Zone.get_make_surface(moon)
    local d=Zone.get_make_surface(moon_orbit)
    for _,zone in ipairs({origin,destination,moon,moon_orbit}) do Zone.discover("player",zone,"Production Flow test fixture") end
    for _,s in ipairs({a,b,c,d}) do
      s.request_to_generate_chunks({0,0},5);s.force_generate_chunk_requests()
      local tiles={}
      for x=-96,96 do for y=-96,96 do tiles[#tiles+1]={name=Zone.is_space(Zone.from_surface(s)) and "se-space-platform-plating" or "refined-concrete",position={x,y}} end end
      s.set_tiles(tiles,true)
      for _,e in pairs(s.find_entities_filtered{area={{-96,-96},{96,96}},type={"tree","simple-entity","cliff","resource","unit","unit-spawner"}}) do e.destroy() end
    end
    storage.pf_fixture={pads={},rockets={},expected={},truth={},scenarios={},launch_schedule={},cannon_schedule={},
      cannons={},receivers={},cannon_targets={},stat_deltas={},samples={},stat_items={},zones={origin.index,destination.index,moon.index,moon_orbit.index},
      origin=origin.index,destination=destination.index}
    local f=storage.pf_fixture
    local function make(s,name,x,y,direction)
      local e=s.create_entity{name=name,position={x,y},direction=direction,force="player",raise_built=true}
      assert(e and e.valid,"Failed creating "..name)
      e.destructible=false
      return e
    end
    local function pad(name,s,x,y)
      local entity=make(s,"cargo-landing-pad",x,y)
      f.pads[name]=entity
      local struct=Landingpad.from_entity(entity);assert(struct)
      Landingpad.rename(struct,"Fixture-"..name);struct.grace_period_until=0
      return "Fixture-"..name
    end
    pad("origin",a,-32,0);pad("destination",b,-32,0)
    local function rocket(name,tick,s,x,y,zone,pad_name,items)
      local e=make(s,"se-rocket-launch-pad",x,y)
      local r=Launchpad.from_entity(e);assert(r)
      r.destination={zone=zone,landing_pad_name=pad_name}
      r.rocket_sections=100;r.crew_capsules=1;r.lua_fuel=10000000
      for _,stack in ipairs(items) do assert(e.insert(stack)==stack.count) end
      f.expected[e.unit_number]=e.get_inventory(defines.inventory.chest).get_contents()
      Launchpad.prep(r);r.silo.rocket_parts=100;r.silo.energy=1000000000
      f.rockets[name]=e.unit_number
      local delta=Zone.get_travel_delta_v(r.zone,zone)
      f.scenarios[name]={unit=e.unit_number,from=s.name,to=Zone.get_surface(zone).name,from_zone=Zone.from_surface(s).index,
        to_zone=zone.index,pad_name=pad_name,tick=tick,
        cargo_loss=Launchpad.get_cargo_loss(e.force,zone,delta),
        pad_miss=pad_name and Launchpad.get_survivability_loss(e.force,zone,delta) or 1}
      f.launch_schedule[#f.launch_schedule+1]={name=name,tick=tick}
    end
    -- The original three IDs/names/manifests and early in-flight checkpoint stay.
    rocket("outbound",120,a,0,0,destination,"Fixture-destination",{{name="iron-plate",count=1000},{name="copper-plate",count=500},{name="water-barrel",count=20}})
    rocket("inbound",180,b,0,0,origin,"Fixture-origin",{{name="iron-ore",count=800},{name="copper-ore",count=400}})
    rocket("padless",240,a,32,0,destination,nil,{{name="steel-plate",count=200}})
    -- Unique receiving pads avoid reserve/full-pad races between real rockets.
    rocket("orbit-return",3600,b,32,-32,origin,pad("orbit-return",a,-64,0),{{name="iron-plate",count=650},{name="electronic-circuit",count=100}})
    rocket("moon-export",6000,a,0,-32,moon,pad("moon-export",c,-32,0),{{name="iron-plate",count=1800},{name="iron-gear-wheel",count=120}})
    rocket("moon-import",9000,c,0,0,origin,pad("moon-import",a,-32,-32),{{name="iron-plate",count=900},{name="copper-plate",count=300}})
    rocket("moon-orbit-export",12000,a,32,-32,moon_orbit,pad("moon-orbit-export",d,-32,0),{{name="iron-plate",count=750},{name="solid-fuel",count=200}})
    rocket("moon-orbit-import",15000,d,0,0,origin,pad("moon-orbit-import",a,-64,-32),{{name="iron-plate",count=1350},{name="electronic-circuit",count=250}})
    rocket("orbit-supply",18000,a,64,-32,destination,pad("orbit-supply",b,-32,-32),{{name="iron-plate",count=450},{name="stone-brick",count=800}})
    rocket("moon-second-export",21000,a,0,-64,moon,pad("moon-second-export",c,-32,-32),{{name="iron-plate",count=2200},{name="steel-plate",count=250}})
    rocket("moon-second-import",24000,c,32,-32,origin,pad("moon-second-import",a,-32,-64),{{name="iron-plate",count=500},{name="copper-ore",count=350}})
    rocket("moon-orbit-second-import",27000,d,32,-32,origin,pad("moon-orbit-second-import",a,-64,-64),{{name="iron-plate",count=1750},{name="battery",count=150}})
    for name,recipe in pairs(prototypes.recipe) do
      if name:find("se-delivery-cannon-pack-",1,true) then
        for _,ing in pairs(recipe.ingredients) do
          if ing.name=="iron-plate" then f.cannon_recipe=name;f.cannon_package=recipe.products[1].name;f.cannon_amount=ing.amount end
        end
      end
    end
    assert(f.cannon_recipe,"Missing cannon iron-plate recipe")
    local function cannon(name,x,target,target_surface,receiver_x)
      local entity=make(a,"se-delivery-cannon",x,32)
      local receiver=make(target_surface,"se-delivery-cannon-chest",receiver_x,32)
      f.cannons[name]=entity;f.receivers[name]=receiver
      f.cannon_targets[name]={zone=target,receiver=name}
      local struct=DeliveryCannon.from_entity(entity);assert(struct)
      assert(DeliveryCannon.is_reachable_destination(struct,target),"Fixture cannon target is unreachable")
      struct.destination={zone=target,coordinate=receiver.position};struct.mode=DeliveryCannon.mode_off
      entity.set_recipe(f.cannon_recipe)
      return entity,receiver
    end
    f.cannon,f.receiver=cannon("primary",0,destination,b,0)
    cannon("moon",24,moon,c,0);cannon("moon-orbit",48,moon_orbit,d,0);cannon("orbit-secondary",72,destination,b,24)
    f.cannon_schedule={{tick=300,name="primary",miss=false},{tick=600,name="primary",miss=true},
      {tick=3600,name="moon",miss=false},{tick=7200,name="orbit-secondary",miss=false},
      {tick=10800,name="moon-orbit",miss=false},{tick=14400,name="moon",miss=false},
      {tick=18000,name="orbit-secondary",miss=false},{tick=21600,name="moon-orbit",miss=false},
      {tick=25200,name="moon",miss=false},{tick=27000,name="moon-orbit",miss=false}}
    -- Real enclosed ship; SE's own integrity algorithm must accept it.
    local floor={}
    for x=48,65 do for y=48,65 do floor[#floor+1]={name="se-spaceship-floor",position={x,y}} end end
    b.set_tiles(floor,true)
    for x=48,65 do make(b,"se-spaceship-wall",x+0.5,48.5);make(b,"se-spaceship-wall",x+0.5,65.5) end
    for y=49,64 do make(b,"se-spaceship-wall",48.5,y+0.5);make(b,"se-spaceship-wall",65.5,y+0.5) end
    local chest=make(b,"steel-chest",55.5,53.5)
    chest.insert{name="electronic-circuit",count=100};chest.insert{name="steel-plate",count=50}
    local tank=make(b,"storage-tank",61.5,53.5);tank.set_fluid(1,{name="water",amount=1000})
    local booster=make(b,"se-spaceship-rocket-booster-tank",61.5,60.5)
    booster.set_fluid(1,{name="se-liquid-rocket-fuel",amount=100000})
    local console=make(b,"se-spaceship-console",52.5,58.5)
    local ship=Spaceship.from_entity(console);assert(ship);ship.name="Fixture Courier";f.ship=ship.index
    for i=1,3 do game.forces.player.technologies["se-spaceship-integrity-"..i].researched=true end
    SpaceshipIntegrity.start_integrity_check(ship,0)
    local tries=0
    while ship.is_doing_check and tries<10000 do SpaceshipIntegrity.integrity_check_tick(ship);tries=tries+1 end
    assert(ship.integrity_valid,"Ship integrity failed: "..serpent.line(ship.check_message))
    emit("SHIP_READY",ship_manifest())
    build_factory(a,make)
    for _,stacks in pairs(f.expected) do for _,stack in pairs(stacks) do f.stat_items[stack.name]=true end end
    for _,name in ipairs({"iron-plate","iron-ore","copper-plate","copper-cable","electronic-circuit","iron-gear-wheel","stone-tablet",f.cannon_package}) do f.stat_items[name]=true end
    factory_sample()
    return metadata()
  end,
  launch=function(name)
    local f=storage.pf_fixture
    local r=Launchpad.from_unit_number(assert(f.rockets[name]))
    emit("BEFORE_LAUNCH",{name=name,tick=game.tick,manifest=contents(r.container,defines.inventory.chest)})
    local boundary=begin_boundary("rocket_dispatch",{r.container.surface,Zone.get_make_surface(r.destination.zone)},
      {name=name,unit=r.container.unit_number,manifest=contents(r.container,defines.inventory.chest)})
    boundary.endpoint_before=contents(r.container,defines.inventory.chest)
    Launchpad.launch(r,false)
    boundary.endpoint_after=contents(r.container,defines.inventory.chest);end_boundary(boundary)
    assert(r.launch_status==1,"Launch not accepted: "..name)
    f.scenarios[name].launched_tick=game.tick
  end,
  fire=function(name,miss)
    -- Keep the original fire(false/true) test interface usable.
    if type(name)=="boolean" then miss=name;name="primary" end
    name=name or "primary"
    local f=storage.pf_fixture;local entity=assert(f.cannons[name]);local target=f.cannon_targets[name]
    local receiver=f.receivers[target.receiver]
    assert(receiver and receiver.valid,"Missing cannon catcher: "..name)
    local destination={zone=target.zone,coordinate=receiver.position}
    local position=miss and CANNON_MISS or destination.coordinate
    local target_surface=Zone.get_make_surface(target.zone)
    local aimed_at=catcher_at(target_surface,position)
    assert((miss and not aimed_at) or (not miss and aimed_at==receiver),"Wrong cannon target: "..name)
    local r=DeliveryCannon.from_entity(entity)
    r.mode=DeliveryCannon.mode_single_target
    r.destination={zone=target.zone,coordinate=position}
    r.required_energy=nil;r.energy_interface.energy=1000000000
    assert(entity.get_output_inventory().insert{name=f.cannon_package,count=1}==1)
    local before=count(storage.delivery_cannon_payloads)
    local boundary=begin_boundary("cannon_dispatch",{entity.surface,target_surface},
      {name=name,unit=entity.unit_number,item="iron-plate",count=f.cannon_amount,package=f.cannon_package,package_seeded_by_fixture=true,miss=miss})
    boundary.endpoint_before=contents(entity,defines.inventory.crafter_output)
    DeliveryCannon.attempt_fire(r)
    -- The in-flight payload owns its target. Restore the launcher's aim even
    -- when the fixture deliberately fired at an empty tile.
    r.destination=destination
    r.mode=DeliveryCannon.mode_off
    boundary.endpoint_after=contents(entity,defines.inventory.crafter_output);end_boundary(boundary)
    assert(count(storage.delivery_cannon_payloads)==before+1,"Cannon did not fire: "..name)
    emit("CANNON_FIRE",{tick=game.tick,name=name,source=entity.unit_number,target=target.zone.name,item="iron-plate",count=f.cannon_amount,miss=miss})
  end,
  metadata=metadata,
  sample=factory_sample,
  diagnose=factory_diagnostics,
  snapshot=snapshot,
  checkpoint=function()
    local r=snapshot()
    local active,prepared=0,0
    for name,v in pairs(r.rockets) do
      if storage.pf_fixture.scenarios[name].launched_tick then
        assert(v.status==2,"Launched rocket not in flight at checkpoint: "..name);active=active+1
      else prepared=prepared+1 end
    end
    assert(active>0 and active+prepared==#storage.pf_fixture.launch_schedule)
    r.checkpoint_counts={inflight=active,prepared=prepared}
    return r
  end,
  ship_launch=function()
    local ship=Spaceship.from_index(storage.pf_fixture.ship)
    storage.pf_fixture.ship_departure=ship_manifest()
    ship.is_launching=true;ship.surface_lock_timeout=0
    Spaceship.launch(ship)
    assert(ship.on_own_surface,"Ship did not launch")
  end,
  ship_anchor=function()
    local ship=Spaceship.from_index(storage.pf_fixture.ship)
    -- Position near Nauvis to isolate clone/anchor and manifest accounting.
    -- This does not exercise navigation, engines or travel-time simulation.
    ship.near={type="zone",index=storage.pf_fixture.origin};ship.surface_lock_timeout=0
    Spaceship.land_at_position(ship,{x=60,y=60})
    assert(ship.zone_index==storage.pf_fixture.origin,"Ship did not anchor")
    storage.pf_fixture.ship_arrival=ship_manifest()
  end,
  ship_unload=function()
    local ship=Spaceship.from_index(storage.pf_fixture.ship)
    local surface=ship.console.surface
    local chests=surface.find_entities_filtered{area=ship.known_bounds,name="steel-chest"}
    assert(#chests==1)
    assert(chests[1].remove_item{name="electronic-circuit",count=40}==40)
    local receiver=surface.create_entity{name="steel-chest",position={85,60},force="player",raise_built=true}
    receiver.insert{name="electronic-circuit",count=40}
    local tanks=surface.find_entities_filtered{area=ship.known_bounds,name="storage-tank"}
    assert(#tanks==1);local removed=tanks[1].remove_fluid(1,250);assert(removed and removed.amount==250)
    local tank=surface.create_entity{name="storage-tank",position={90,60},force="player",raise_built=true}
    tank.set_fluid(1,{name="water",amount=250})
    storage.pf_fixture.ship_after_unload=ship_manifest()
    emit("SHIP_UNLOAD",{departure=storage.pf_fixture.ship_departure,arrival=storage.pf_fixture.ship_arrival,after=storage.pf_fixture.ship_after_unload})
  end,
  verify=function()
    local diagnostic=factory_diagnostics()
    emit("FACTORY_DIAGNOSTICS",diagnostic)
    helpers.write_file("se-fixture-factory-diagnostics.json",helpers.table_to_json(diagnostic),false)
    local r=snapshot();local lands,caught,missed=0,0,0
    for _,v in ipairs(r.truth) do
      if v.kind=="rocket_land" then lands=lands+1
      elseif v.kind=="cannon_land" then
        if v.receiver then
          assert(v.caught==v.count,"Catcher failed to receive the full cannon payload")
          caught=caught+1
        else
          assert(v.caught==0,"Cannon miss gained catcher stock")
          missed=missed+1
        end
      end
    end
    local contract=metadata()
    assert(lands==contract.counts.rockets,"Rocket landing count mismatch: "..lands)
    assert(missed==1 and caught==contract.counts.cannon_shots-missed,"Cannon hit/miss count mismatch")
    r.cannon_impacts={caught=caught,missed=missed}
    r.cannon_aim={}
    for _,receiver in ipairs(contract.receivers) do
      local catcher=storage.pf_fixture.receivers[receiver.name]
      local cannon=DeliveryCannon.from_entity(storage.pf_fixture.cannons[receiver.name])
      local destination=assert(cannon.destination,"Cannon lost its destination: "..receiver.name)
      local target_surface=Zone.get_surface(destination.zone)
      assert(target_surface==catcher.surface and catcher_at(target_surface,destination.coordinate)==catcher,
        "Cannon was left aimed away from its catcher: "..receiver.name)
      assert(amount(contents(catcher,defines.inventory.chest),receiver.item)==receiver.count,"Receiver physical contents mismatch: "..receiver.name)
      r.cannon_aim[receiver.name]={surface=target_surface.name,position=destination.coordinate,receiver=catcher.unit_number}
    end
    r.contract=contract
    assert(amount(r.receiver,"iron-plate")==storage.pf_fixture.cannon_amount,"Receiver manifest mismatch")
    assert(amount(r.pads.destination,"iron-plate")>0,"Outbound cargo missing")
    assert(amount(r.pads.origin,"iron-ore")>0,"Inbound cargo missing")
    for _,v in ipairs(r.truth) do
      if v.kind=="rocket_land" and v.had_pad then
        for _,stack in pairs(v.surviving_manifest) do
          assert(amount(v.after,stack.name)-amount(v.before,stack.name)==stack.count,"Landing-pad inventory delta mismatch")
        end
      end
    end
    local surface=Zone.get_surface(Zone.from_zone_index(storage.pf_fixture.destination))
    local spilled=0
    for _,e in pairs(surface.find_entities_filtered{type="item-entity",area={{12,12},{52,52}}}) do
      if e.stack.valid_for_read and e.stack.name=="iron-plate" then spilled=spilled+e.stack.count end
    end
    assert(spilled==math.ceil(storage.pf_fixture.cannon_amount/4),"Unexpected cannon miss spill: "..spilled)
    r.cannon_spilled_items={['iron-plate']=spilled}
    local f=storage.pf_fixture
    assert(f.ship_departure.items["electronic-circuit"]==100)
    assert(f.ship_arrival.items["electronic-circuit"]==100)
    assert(f.ship_after_unload.items["electronic-circuit"]==60)
    assert(f.ship_departure.fluids.water==1000 and f.ship_arrival.fluids.water==1000 and f.ship_after_unload.fluids.water==750)
    r.ship_accounting={departure=f.ship_departure,arrival=f.ship_arrival,after_unload=f.ship_after_unload}
    local first,last=f.samples[1],f.samples[#f.samples]
    assert(#f.samples>=50,"Missing real working-factory measurement samples")
    for name,entity in pairs(f.factory.machines) do assert(entity.products_finished>0,"Factory machine never crafted: "..name) end
    assert(amount(contents(f.factory.chests["gear-output"],defines.inventory.chest),"iron-gear-wheel")>0,"Working factory has no gears")
    assert(amount(contents(f.factory.chests["circuit-output"],defines.inventory.chest),"electronic-circuit")>0,"Working factory has no circuits")
    assert(amount(last.chests["iron-ore-feed-1"],"iron-ore")<amount(first.chests["iron-ore-feed-1"],"iron-ore"),"Real furnace feed never decreased")
    assert(amount(last.chests["iron-plate-stock-3"],"iron-plate")>amount(first.chests["iron-plate-stock-3"],"iron-plate"),"Real smelted stock never increased")
    local boundary_counts={};for _,boundary in ipairs(f.stat_deltas) do boundary_counts[boundary.kind]=(boundary_counts[boundary.kind] or 0)+1 end
    assert(boundary_counts.rocket_dispatch==contract.counts.rockets and boundary_counts.rocket_arrival==contract.counts.rockets)
    assert(boundary_counts.cannon_dispatch==contract.counts.cannon_shots and boundary_counts.cannon_arrival==contract.counts.cannon_shots)
    r.factory=f.factory.descriptor;r.stat_deltas=f.stat_deltas;r.measurement_data=export_measurements()
    r.measurement_exports={json="se-fixture-measurements.json",tsv="se-fixture-measurements.tsv",boundary_tsv="se-fixture-boundary-deltas.tsv"}
    emit("FACTORY_PASS",{samples=#f.samples,machines=#f.factory.descriptor.machines,boundaries=boundary_counts,
      first_tick=first.tick,last_tick=last.tick,ore_feed_before=amount(first.chests["iron-ore-feed-1"],"iron-ore"),
      ore_feed_after=amount(last.chests["iron-ore-feed-1"],"iron-ore"),iron_stock_after=amount(last.chests["iron-plate-stock-3"],"iron-plate")})
    return r
  end
})
