local function trace(s) log('TRAIN TRACE '..game.tick..' '..s) end
local function describe(t)
 local s=t.station
 return 'state='..t.state..' station='..(s and s.backer_name or 'nil')..' speed='..t.speed..' position='..serpent.line(storage.loco.position)..' items='..serpent.line(t.get_contents())..' fluids='..serpent.line(t.get_fluid_contents())
end
script.on_init(function()
 local s=game.surfaces[1]
 s.request_to_generate_chunks({0,0},5); s.force_generate_chunk_requests()
 for _,e in pairs(s.find_entities_filtered{area={{-12,-110},{12,110}},type={'tree','simple-entity','cliff'}}) do e.destroy() end
 for y=-100,100,2 do assert(s.create_entity{name='straight-rail',position={0,y},direction=defines.direction.north,force='player'}) end
 for i,y in ipairs({50,0,-50}) do
  local stop=assert(s.create_entity{name='train-stop',position={2,y},direction=defines.direction.north,force='player'})
  stop.backer_name='Station '..i
  assert(stop.connected_rail)
 end
 local loco=assert(s.create_entity{name='locomotive',position={0,85},orientation=0,force='player'})
 local wagon=assert(s.create_entity{name='cargo-wagon',position={0,92},orientation=0,force='player'})
 local fluid=assert(s.create_entity{name='fluid-wagon',position={0,99},orientation=0,force='player'})
 loco.get_fuel_inventory().insert{name='coal',count=50}
 wagon.get_inventory(defines.inventory.cargo_wagon).insert{name='iron-plate',count=100}
 fluid.set_fluid(1,{name='water',amount=10000})
 storage.loco=loco; storage.wagon=wagon; storage.fluid=fluid; storage.arrivals={}; storage.exits={}
 local t=loco.train
 assert(#t.carriages==3)
 trace('setup '..describe(t))
 t.schedule={current=1,records={{station='Station 1',wait_conditions={{type='time',compare_type='and',ticks=180}}},{station='Station 2',wait_conditions={{type='time',compare_type='and',ticks=180}}},{station='Station 3',wait_conditions={{type='time',compare_type='and',ticks=180}}}}}
 t.manual_mode=false
end)
script.on_event(defines.events.on_train_changed_state,function(e)
 local t=e.train
 trace('event old='..e.old_state..' '..describe(t))
 if t.state==defines.train_state.wait_station and t.station then
  local name=t.station.backer_name
  storage.arrivals[name]={items=t.get_item_count('iron-plate'),water=t.get_fluid_contents().water}
 elseif e.old_state==defines.train_state.wait_station then
  storage.exits[#storage.exits+1]={state=t.state,station=t.station and t.station.backer_name,items=t.get_item_count('iron-plate'),water=t.get_fluid_contents().water}
 end
end)
script.on_event(defines.events.on_tick,function(e)
 local t=storage.loco.train
 if e.tick<1500 then trace('tick '..describe(t)) end
 if t.state==defines.train_state.wait_station and t.station and t.station.backer_name=='Station 2' and not storage.unloaded then
  storage.unloaded=true
  assert(storage.wagon.get_inventory(defines.inventory.cargo_wagon).remove{name='iron-plate',count=40}==40)
  storage.fluid.set_fluid(1,{name='water',amount=6000})
  trace('ground truth partial unload '..describe(t))
 end
 if e.tick==1500 then
  assert(storage.arrivals['Station 1'].items==100 and storage.arrivals['Station 1'].water==10000)
  assert(storage.arrivals['Station 2'].items==100 and storage.arrivals['Station 2'].water==10000)
  assert(storage.arrivals['Station 3'].items==60 and storage.arrivals['Station 3'].water==6000)
  assert(#storage.exits==3 and storage.exits[1].items==100 and storage.exits[1].water==10000)
  assert(storage.exits[2].items==60 and storage.exits[2].water==6000)
  assert(storage.exits[3].state==defines.train_state.no_path and storage.exits[3].station==nil and t.speed==0)
  trace('assertions passed; last exit is no_path with no movement')
  log('TRAIN WITNESS PASS')
 end
end)
