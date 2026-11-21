local function trace(s) log('TRAIN TRACE '..game.tick..' '..s) end
local function describe(t)
 local s=t.station
 return 'state='..t.state..' station='..(s and s.backer_name or 'nil')..' speed='..t.speed..' position='..serpent.line(storage.loco.position)..' items='..serpent.line(t.get_contents())..' fluids='..serpent.line(t.get_fluid_contents())
end

local function cargo(train)
 return {items=train.get_item_count('iron-plate'),water=train.get_fluid_contents().water}
end

local function observe_stop(stop)
 local scheduled={}
 for _,train in ipairs(stop.get_train_stop_trains()) do scheduled[#scheduled+1]=train.id end
 table.sort(scheduled)
 local headed={}
 for _,train in ipairs(game.train_manager.get_trains{surface=stop.surface,force=stop.force}) do
  if train.has_path and train.path_end_stop==stop and train.station~=stop then
   headed[#headed+1]=train.id
  end
 end
 local parked=stop.get_stopped_train()
 return {unit=stop.unit_number,scheduled=scheduled,headed=headed,
  parked=parked and parked.id,reservations=stop.trains_count,limit=stop.trains_limit}
end

script.on_init(function()
 local s=game.surfaces[1]
 s.request_to_generate_chunks({0,0},5); s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities_filtered{area={{-12,-110},{12,110}},type={'tree','simple-entity','cliff'}}) do e.destroy() end
 for y=-100,100,2 do assert(s.create_entity{name='straight-rail',position={0,y},direction=defines.direction.north,force='player'}) end
 for i,y in ipairs({50,0,-50,-76}) do
  local stop=assert(s.create_entity{name='train-stop',position={2,y},direction=defines.direction.north,force='player'})
  stop.backer_name='Station '..(i==4 and 2 or i)
  assert(stop.connected_rail)
  if i==2 then storage.drop_stop=stop end
  if i==4 then storage.same_name_stop=stop; stop.trains_limit=0 end
 end
 local loco=assert(s.create_entity{name='locomotive',position={0,85},orientation=0,force='player'})
 local wagon=assert(s.create_entity{name='cargo-wagon',position={0,92},orientation=0,force='player'})
 local fluid=assert(s.create_entity{name='fluid-wagon',position={0,99},orientation=0,force='player'})
 loco.get_fuel_inventory().insert{name='coal',count=50}
 wagon.get_inventory(defines.inventory.cargo_wagon).insert{name='iron-plate',count=100}
 fluid.set_fluid(1,{name='water',amount=10000})
 local idle=assert(s.create_entity{name='locomotive',position={0,-96},orientation=0,force='player'})
 idle.train.manual_mode=true
 idle.train.schedule={current=1,records={{station='Station 2'}}}
 storage.loco=loco; storage.wagon=wagon; storage.fluid=fluid
 storage.arrivals={}; storage.exits={}; storage.departures={}
 local t=loco.train
 assert(#t.carriages==3)
 trace('setup '..describe(t))
 t.schedule={current=1,records={{station='Station 1',wait_conditions={{type='time',compare_type='and',ticks=180}}},{station='Station 2',wait_conditions={{type='time',compare_type='and',ticks=180}}},{station='Station 3',wait_conditions={{type='time',compare_type='and',ticks=180}}}}}
 t.manual_mode=false
end)
script.on_event(defines.events.on_train_changed_state,function(e)
 local t=e.train
 if not storage.loco or t.id~=storage.loco.train.id then return end
 trace('event old='..e.old_state..' '..describe(t))
 if t.state==defines.train_state.wait_station and t.station then
  local name=t.station.backer_name
  storage.arrivals[name]=cargo(t)
  storage.last_stop=name
 elseif e.old_state==defines.train_state.wait_station then
  local exit=cargo(t)
  exit.state,exit.station=t.state,t.station and t.station.backer_name
  storage.exits[#storage.exits+1]=exit
  storage.pending_departure={stop=storage.last_stop,y=storage.loco.position.y,exit=exit}
 end
end)
script.on_event(defines.events.on_tick,function(e)
 local t=storage.loco.train
 if e.tick<1500 then trace('tick '..describe(t)) end
 local departed=storage.pending_departure
 if departed and storage.loco.position.y<departed.y-2 then
  storage.departures[departed.stop]=departed.exit
  storage.pending_departure=nil
  trace('observed northbound movement after exit '..departed.stop)
 end
 if not storage.approach and t.has_path and t.path_end_stop==storage.drop_stop and t.station~=storage.drop_stop then
  storage.approach={target=observe_stop(storage.drop_stop),same_name=observe_stop(storage.same_name_stop)}
  trace('approach '..serpent.line(storage.approach))
 end
 if t.state==defines.train_state.wait_station and t.station and t.station.backer_name=='Station 1' and not storage.loaded then
  storage.loaded=true
  assert(storage.wagon.get_inventory(defines.inventory.cargo_wagon).insert{name='iron-plate',count=40}==40)
  storage.fluid.set_fluid(1,{name='water',amount=14000})
  trace('ground truth load '..describe(t))
 end
 if t.state==defines.train_state.wait_station and t.station and t.station.backer_name=='Station 2' and not storage.unloaded then
  storage.unloaded=true
  storage.parked_at_drop=observe_stop(storage.drop_stop)
  trace('parked at drop '..serpent.line(storage.parked_at_drop))
  assert(storage.wagon.get_inventory(defines.inventory.cargo_wagon).remove{name='iron-plate',count=60}==60)
  storage.fluid.set_fluid(1,{name='water',amount=7000})
  trace('ground truth partial unload '..describe(t))
 end
 if e.tick==1500 then
  assert(storage.arrivals['Station 1'].items==100 and storage.arrivals['Station 1'].water==10000)
  assert(storage.arrivals['Station 2'].items==140 and storage.arrivals['Station 2'].water==14000)
  assert(storage.arrivals['Station 3'].items==80 and storage.arrivals['Station 3'].water==7000)
  assert(#storage.exits==3)
  local load=assert(storage.departures['Station 1'])
  local drop=assert(storage.departures['Station 2'])
  assert(load.items==140 and load.water==14000 and drop.items==80 and drop.water==7000)
  assert(storage.exits[3].state==defines.train_state.no_path and storage.exits[3].station==nil and t.speed==0)
  assert(not storage.departures['Station 3'], 'A train with no path stayed at Station 3')
  local target,same_name=storage.approach.target,storage.approach.same_name
  assert(target.unit~=same_name.unit and #target.headed==1 and target.headed[1]==t.id and #same_name.headed==0)
  assert(not target.parked and storage.parked_at_drop.parked==t.id and #storage.parked_at_drop.headed==0)
  assert(target.reservations==1 and same_name.reservations==0 and storage.parked_at_drop.reservations==1)
  for _,sample in ipairs({target,same_name}) do
   local matched=false
   for _,id in ipairs(sample.scheduled) do if id==t.id then matched=true end end
   assert(matched and #sample.scheduled==2, 'Both stops match the two trains scheduled by name, including the idle train')
  end
  trace('assertions passed; last exit is no_path with no movement')
  log('TRAIN WITNESS PASS')
 end
end)
