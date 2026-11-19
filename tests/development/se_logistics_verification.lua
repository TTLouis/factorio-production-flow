-- Private test interface in Production Flow's own script/storage context.
-- The scenario contract contains planned inputs/current-stock expectations; it
-- never writes shipment observations, inferred payloads or received amounts.
-- Production Flow's own receipts are exported for the harness to compare with
-- the private SE ground truth; this file never reads that truth.
local Rockets=require("scripts.se_rockets")
local Cannons=require("scripts.se_cannons")
local Endpoints=require("scripts.transfer_endpoints")
local ChestStock=require("scripts.chest_stock")
local History=require("scripts.history")
local Data=require("scripts.se_transfer_data")
local Exchanges=require("scripts.transfer_exchanges")
-- Private cadence/retention only. Every retained value is the untouched result
-- of the shipping bounded inventory scanner, never a constructed stock sample.
local stock_tick=ChestStock.tick
ChestStock.interval=function() return 1800 end
ChestStock.tick=function(tick)
  stock_tick(tick)
  if storage.test_real_stock_basis~=storage.stock_basis then
    storage.test_real_stock_basis=storage.stock_basis;storage.test_real_stock_scans={}
  end
  local retained=storage.test_real_stock_scans or {};storage.test_real_stock_scans=retained
  local history=storage.stock or {};local latest=history[#history]
  if latest and (not retained[#retained] or retained[#retained].tick~=latest.tick) then
    retained[#retained+1]=latest
    while #retained>128 do table.remove(retained,1) end
    -- The production scan routine prunes its display ring to seven. Extend
    -- only this disposable fixture's retention using the actual scan objects.
    local display={};for i,scan in ipairs(retained) do display[i]=scan end
    storage.stock=display
  end
end
local function measured_stock()
  local scans=storage.test_real_stock_scans or {}
  local result={source="shipping ChestStock.tick completed scans",synthetic=false,
    basis=storage.stock_basis,cooldown_ticks=1800,private_retention_limit=128,
    scans=#scans,first_tick=scans[1] and scans[1].tick,last_tick=scans[#scans] and scans[#scans].tick}
  return result,scans
end
local function export_sampler_history(surface)
  local provenance,scans=measured_stock()
  local iron=History.build(surface.index,3600,"item/iron-plate")
  local result={provenance=provenance,stock_scans=scans,iron_plate_history=iron}
  helpers.write_file("se-fixture-sampler-history.json",helpers.table_to_json(result),false)
  return provenance
end
local function same_amounts(actual,expected,message)
  for name,count in pairs(expected) do assert(actual[name]==count,message..": "..name) end
  for name,count in pairs(actual) do assert(expected[name]==count,message..": unexpected "..name) end
end
remote.add_interface("production-flow-se-verification",{check=function(contract)
  if contract then storage.test_se_fixture_contract=contract end
  contract=assert(storage.test_se_fixture_contract,"Missing isolated SE fixture input contract")
  assert(contract.contract_version==2,"Unsupported SE fixture contract")
  local force=game.forces.player
  local all={}
  local source_units={}
  local crash_pods={}
  local total_effects=0
  local named_padless=assert(contract.scenarios and contract.scenarios.padless,"Missing named padless input scenario")
  local named_padless_status
  local rocket_scenarios,safety_estimates={},{}
  local rocket_receipts,cannon_receipts,seen_rockets,seen_cannons={},{},{},{}
  for name,scenario in pairs(contract.scenarios) do rocket_scenarios[scenario.unit]=name end
  for _,scope in ipairs(contract.surfaces) do
    local surface=assert(game.surfaces[scope.surface_index]);local expected=contract.by_surface[surface.name]
    if prototypes.entity["se-cargo-rocket-cargo-pod"] then
      for _,pod in pairs(surface.find_entities_filtered{name="se-cargo-rocket-cargo-pod",force=force}) do
        assert(storage.chest_stock.entities[pod.unit_number]==pod,"Public SE crash pod missing from shipping stock registry")
        local stacks=pod.get_inventory(defines.inventory.chest).get_contents();local iron=0
        for _,item in pairs(stacks) do if item.name=="iron-plate" then iron=iron+item.count end end
        local latest=storage.stock[#storage.stock];local quantity=latest and latest.s[surface.index] and latest.s[surface.index]["item/iron-plate"] or 0
        assert(quantity>=iron,"Completed shipping stock scan excludes crash-pod iron")
        crash_pods[#crash_pods+1]={unit=pod.unit_number,surface=surface.name,items=stacks,iron=iron,
          latest_scan_tick=latest and latest.tick,latest_scan_iron=quantity,registered=true}
      end
    end
    local q=Rockets.query(force,surface,game.tick,3600)
    assert(q.shipments==expected.shipments and #q.imports==expected.import_routes and #q.exports==expected.export_routes,
      "Native directional ledger mismatch on "..surface.name)
    local sent,padless,materials={},0,{}
    for _,r in ipairs(q.records) do
      if r.received~=nil then
        assert(r.status=="received" and r.receipt=="pad" and r.arrival_tick==r.landed_tick,"Unverified rocket receipt")
      else
        assert(r.arrival_tick==nil,"Arrival without a measured receipt")
      end
      if r.status=="padless" then assert(r.received==nil,"Padless rocket claimed a pad receipt") end
      assert(r.cargo_inventory==nil and r.landing_entity==nil,"Rocket still tracked after the fixture finished")
      if not seen_rockets[r.id] then
        seen_rockets[r.id]=true
        rocket_receipts[#rocket_receipts+1]={unit=r.launch_pad,departure_tick=r.departure_tick,landed_tick=r.landed_tick,
          arrival_tick=r.arrival_tick,status=r.status,receipt=r.receipt,landing_pad=r.landing_pad,to=r.to.name,
          sent=r.sent,received=r.received}
      end
      local scenario=contract.scenarios[assert(rocket_scenarios[r.launch_pad])]
      assert(r.cargo_loss and math.abs(r.cargo_loss-scenario.cargo_loss)<1e-9,"Launch loss differs from SE's native route model")
      assert(r.pad_miss and math.abs(r.pad_miss-scenario.pad_miss)<1e-9,"Pad-miss chance differs from SE's native route model")
      if r.status=="padless" then padless=padless+1 end
      if r.launch_pad==named_padless.unit then
        assert(not named_padless_status or named_padless_status==r.status,"Named padless status differs by surface scope")
        named_padless_status=r.status
      end
      for _,item in ipairs(r.sent) do sent[item.name]=(sent[item.name] or 0)+item.count;materials[item.name]=true end
      assert(Endpoints.resolve(r.sender,force),"Rocket sender endpoint missing after reload")
      if r.landing_pad then assert(Endpoints.resolve(r.receiver,force),"Intended receiver endpoint missing") end
    end
    local data=Data.query(force,surface,game.tick,3600,{direction="imports",method="rocket",timing="either"})
    for _,record in ipairs(data.records) do
      local tick,kind,count,dispatched=Exchanges.observation(record)
      if record.received~=nil then
        assert(kind=="received" and tick==record.arrival_tick and count==Exchanges.amount(record.received),
          "Measured SE rocket receipt did not reach the shipment graph")
      else
        assert(kind=="inbound_estimate" and tick==record.tick and count>0 and count<=dispatched,
          "Real SE inbound rocket did not reach the shipment-graph estimate")
        assert(record.arrival_tick==nil)
        safety_estimates[rocket_scenarios[record.sender.unit_number]]={estimated=count,sent=dispatched,status=record.status,
          loss=record.cargo_loss,pad_miss=record.pad_miss}
      end
    end
    same_amounts(sent,expected.sent,"Exact witnessed sent manifest mismatch on "..surface.name)
    local cannon=Cannons.query(force,surface,game.tick,3600)
    -- Queries now also list shots landing here; count only local senders.
    local local_shots=0
    for _,r in ipairs(cannon.observations) do
      if r.sender.surface==surface then
        local_shots=local_shots+1
        assert(Endpoints.resolve(r.sender,force),"Cannon sender missing")
        source_units[r.sender.unit_number]=true
      end
      assert(r.sent and #r.sent==1,"Cannon shot lost its fired package")
      assert(r.destination and r.destination.surface.valid,"Fixture cannon shot was not paired with its projectile")
      if r.received~=nil then
        assert(r.status=="received" and r.arrival_tick==r.eta and r.receiver,"Unverified cannon receipt")
      else
        assert(r.status=="spilled" or r.status=="arrived" or r.status=="lost","Unsettled cannon shot: "..tostring(r.status))
      end
      if not seen_cannons[r.id] then
        seen_cannons[r.id]=true
        cannon_receipts[#cannon_receipts+1]={sender=r.sender.unit_number,tick=r.tick,eta=r.eta,status=r.status,
          package=r.package,sent=r.sent,received=r.received,arrival_tick=r.arrival_tick,
          destination={surface=r.destination.surface.name,zone=r.destination.name,position=r.destination.position},
          receiver=r.receiver and r.receiver.unit_number}
      end
    end
    assert(local_shots==expected.cannon_effects,"Witnessed cannon firing count mismatch on "..surface.name)
    total_effects=total_effects+local_shots
    local endpoints=Cannons.discover(surface,force)
    assert(#endpoints.cannons==expected.cannon_senders and #endpoints.receivers==expected.cannon_receivers,
      "Known cannon endpoint discovery mismatch on "..surface.name)
    local receiver_by_unit={}
    for _,entry in ipairs(endpoints.cannons) do assert(entry.sent==nil and entry.received==nil) end
    for _,entry in ipairs(endpoints.receivers) do
      assert(entry.received==nil,"Current receiver stock became a received shipment")
      receiver_by_unit[entry.endpoint.unit_number]=entry
    end
    for _,receiver in ipairs(contract.receivers) do
      if receiver.surface==surface.name then
        local actual={}
        for _,item in ipairs(assert(receiver_by_unit[receiver.unit]).stored_items) do actual[item.name]=(actual[item.name] or 0)+item.count end
        same_amounts(actual,{[receiver.item]=receiver.count},"Receiver physical stock snapshot mismatch")
      end
    end
    local names={};for name in pairs(materials) do names[#names+1]=name end;table.sort(names)
    local measured=0
    for _,r in ipairs(q.records) do if r.received then measured=measured+1 end end
    all[surface.name]={shipments=q.shipments,sent=sent,padless=padless,measured_receipts=measured,cannon_effects=local_shots,
      imports=#q.imports,exports=#q.exports,materials=names,endpoints={senders=#endpoints.cannons,receivers=#endpoints.receivers}}
  end
  local sources=0;for _ in pairs(source_units) do sources=sources+1 end
  assert(total_effects==contract.counts.cannon_shots and sources==contract.counts.cannon_senders)
  local origin=assert(all[contract.from])
  assert(named_padless_status=="padless" and origin.padless>=1,"Named genuine padless rocket status missing after reload")
  local surface_names={};for name in pairs(all) do surface_names[#surface_names+1]=name end;table.sort(surface_names)
  local result={};for key,value in pairs(origin) do result[key]=value end
  result.surfaces=surface_names;result.by_surface=all;result.counts=contract.counts;result.finish_tick=contract.finish_tick
  result.named_padless={unit=named_padless.unit,status=named_padless_status}
  result.safety_estimates=safety_estimates
  result.rocket_receipts=rocket_receipts
  result.cannon_receipts=cannon_receipts
  result.crash_pods=crash_pods
  result.factory=contract.factory
  local recovery={containers=0,iron_plate=0}
  for _,scope in ipairs(contract.surfaces) do
    for _,entity in pairs(game.surfaces[scope.surface_index].find_entities_filtered{
      name="se-cargo-rocket-cargo-pod",force=force}) do
      assert(storage.chest_stock.entities[entity.unit_number]==entity,
        "A genuine SE padless cargo container escaped the physical stock registry")
      recovery.containers=recovery.containers+1
      for _,item in pairs(entity.get_inventory(defines.inventory.chest).get_contents()) do
        if item.name=="iron-plate" then recovery.iron_plate=recovery.iron_plate+item.count end
      end
    end
  end
  assert(recovery.containers>0 and recovery.iron_plate>0,"Missing genuine padless cargo stock fixture")
  result.recovered_physical_stock=recovery
  result.measured_stock=export_sampler_history(game.surfaces[contract.from])
  assert(result.measured_stock.scans>=15,"Working fixture did not retain enough genuine completed stock scans")
  log("SE CANNON OBSERVER PASS: "..total_effects.." effects from "..sources.." known senders; paired sent/target and settled receipts; inventory snapshots separate")
  log("SE LOGISTICS COLLECTOR PASS: "..contract.counts.rockets.." public launches across "..#surface_names.." surfaces; exact sent, measured pad receipts and reload")
  return result
end})
