-- Isolated stress-map construction/audit and benchmark setup; never packaged.
local T={}
local cfg=require("scripts.stock_stress_config")
local C=require("scripts.chest_stock")
local SK=require("scripts.sankey_ui")
local started, refreshed
local function build()
  local seed=20261024
  local random=game.create_random_generator(seed)
  local surface=game.create_surface("chest-stress",{width=640,height=640,autoplace_controls={},
    default_enable_all_autoplace_controls=false,autoplace_settings={entity={treat_missing_as_default=false},decorative={treat_missing_as_default=false}}})
  surface.request_to_generate_chunks({0,0},10);surface.force_generate_chunk_requests()
  local tiles={}
  for y=-256,255 do for x=-256,255 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
  surface.set_tiles(tiles)
  surface.always_day=true
  local catalog={}
  for name,p in pairs(prototypes.item) do
    if p.type=="item" and not p.hidden and not p.parameter and not p.spoil_result and not p.spoil_to_trigger_result then catalog[#catalog+1]=name end
  end
  table.sort(catalog);assert(#catalog>=48)
  local names={"steel-chest","passive-provider-chest","active-provider-chest","storage-chest","buffer-chest","requester-chest"}
  local qualities={"normal","uncommon","rare","epic","legendary"}
  local expected,counts,stacks,total={},{},0,0
  for i=1,cfg.count do
    local name=names[(i-1)%#names+1]
    local e=assert(surface.create_entity{name=name,position={-250+2*((i-1)%250),-250+2*math.floor((i-1)/250)},force="player"})
    C.add(e)
    counts[name]=(counts[name] or 0)+1
    local order={};for j=1,#catalog do order[j]=j end
    for j=1,48 do
      local other=random(j,#catalog);order[j],order[other]=order[other],order[j]
      local item=catalog[order[j]]
      local amount=random(1,prototypes.item[item].stack_size)
      local inserted=e.insert{name=item,count=amount,quality=qualities[random(1,#qualities)]}
      assert(inserted==amount,"Fixture inventory did not accept a complete stack")
      expected["item/"..item]=(expected["item/"..item] or 0)+amount
      total=total+amount;stacks=stacks+1
    end
  end
  storage.stress_fixture={seed=seed,count=cfg.count,catalog=#catalog,stacks=stacks,items=total,types=counts,
    surface=surface.index,expected=expected}
  -- Start the complete fixture scan after construction; discard the earlier empty-world scan.
  storage.stock={};storage.chest_stock.batch=nil;storage.chest_stock.next_tick=game.tick+1
  for _,p in pairs(game.connected_players) do p.teleport({-245,-245},surface);p.zoom=0.35 end
  log("STOCK STRESS BUILT "..cfg.count.." chests / "..stacks.." stacks / "..#catalog.." item types")
end

function T.tick(UI,Sampler)
  started=started or game.tick
  local elapsed=game.tick-started
  if cfg.mode=="build" then
    if elapsed==0 then
      for _,p in pairs(game.players) do UI.close(p) end
      build();game.speed=64
    end
    if elapsed%300==0 then log("STOCK STRESS progress "..elapsed.." "..helpers.table_to_json(Sampler.stock_status())) end
    local last=Sampler.stock_status().last
    if elapsed>0 and not storage.stress_fixture.audited and last and last.reads==cfg.count then
      local fixture=storage.stress_fixture
      local actual=Sampler.stock(fixture.surface)
      for key,count in pairs(fixture.expected) do assert(actual[key] and actual[key].count==count,"Wrong stock for "..key) end
      for key,entry in pairs(actual) do assert(fixture.expected[key]==entry.count,"Unexpected stock for "..key) end
      fixture.audited=true;fixture.scan=last
      helpers.write_file("stock-stress/fixture-"..cfg.count..".json",helpers.table_to_json(fixture),false)
      game.auto_save("chests-"..cfg.count)
      local player=game.connected_players[1]
      if player then game.take_screenshot{player=player,surface=game.surfaces[fixture.surface],position={0,-250+math.ceil(cfg.count/250)},
        resolution={1920,1080},zoom=0.08,path="stock-stress/chests-"..cfg.count..".png",show_gui=false} end
      log("STOCK STRESS MAP OK")
    end
  elseif cfg.mode=="capture" then
    local player=assert(game.connected_players[1])
    if elapsed==0 then
      game.speed=1
      local us=storage.ui[player.index] or {};storage.ui[player.index]=us;us.tab_id="balance";us.bal_filter="all";us.surface="chest-stress"
      SK.balance_state(us).focus="item/steel-plate"
      UI.open(player)
    elseif elapsed==60 then
      game.take_screenshot{player=player,resolution={1920,1080},path="stock-stress/balance-stock-only.png",show_gui=true}
    elseif elapsed==120 then
      UI.close(player)
      local surface=game.surfaces[storage.stress_fixture.surface]
      player.teleport({-248,-246},surface);player.zoom=1
    elseif elapsed==150 then
      local surface=game.surfaces[storage.stress_fixture.surface]
      player.opened=assert(surface.find_entities_filtered{area={{-251,-251},{-248,-248}},name="steel-chest"}[1])
    elseif elapsed==180 then
      assert(player.opened and player.opened_gui_type==defines.gui_type.entity,"Native chest window did not open")
      game.take_screenshot{player=player,resolution={1920,1080},path="stock-stress/chest-inventory.png",show_gui=true}
    elseif elapsed==240 then
      game.auto_save("stress-captured");log("STOCK STRESS CAPTURE OK")
    end
  elseif elapsed==0 then
    if cfg.open then
      local player=game.connected_players[1] or game.players[1]
      assert(player,"Open-window benchmark requires a player in the saved map")
      local us=storage.ui[player.index] or {};storage.ui[player.index]=us
      us.tab_id="balance";us.surface=storage.stress_fixture and game.surfaces[storage.stress_fixture.surface].name or "nauvis"
      us.bal_filter="all"
      UI.open(player)
      refreshed=Sampler.stock_known(storage.ui[player.index].sidx)
    else for _,p in pairs(game.players) do UI.close(p) end end
  end
  if cfg.mode=="benchmark" and cfg.open and not refreshed and Sampler.stock_known(storage.ui[game.players[1].index].sidx) then
    UI.refresh(game.players[1]);refreshed=true -- Include newly measured stock-only rows after an upgrade.
  end
  if cfg.mode=="benchmark" and cfg.open and elapsed>0 and game.tick%300==0 and not game.connected_players[1] then
    UI.refresh(game.players[1],true) -- Benchmark players are disconnected; emulate normal 5-second UI refresh.
  end
end
return T
