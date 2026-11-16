return function(handlers)
  local Sm,UI=TREQ('scripts.sampler'),TREQ('scripts.ui')
  local p=game.players[1];local canonical=game.forces.player
  local foreign={name='other',recipes={},index=2}
  local unit=989898
  local e={valid=true,type='assembling-machine',name='assembling-machine-1',unit_number=unit,
    surface=game.surfaces[1],force=foreign,products_finished=0,crafting_speed=3200,
    productivity_bonus=0,crafting_progress=0,bonus_progress=0}
  e.get_recipe=function()return {name='iron-plate'}end
  local function total()
    local n=0
    for _,bin in pairs(storage.bins) do
      local sample=bin.rec[1] and bin.rec[1]['iron-plate']
      if sample then n=n+sample.c end
    end
    return n
  end
  local function advance()
    for _=1,60 do game.tick=game.tick+1;Sm.on_tick(game.tick) end
  end
  local base_capacity=Sm.capacity(1)['iron-plate']
  local base_count=Sm.machine_counts(1)['iron-plate']
  local crafts=total()
  Sm.add(e);e.products_finished=100;advance()
  assert(storage.machines[unit] and storage.machines[unit].r==nil,
    'Foreign machine may be an ownership candidate, never a sampled recipe')
  assert(Sm.capacity(1)['iron-plate']==base_capacity and Sm.machine_counts(1)['iron-plate']==base_count
    and total()==crafts,'Foreign crafts/capacity/counts leaked into player-force accounting')
  e.force=canonical;advance()
  assert(total()==crafts and Sm.capacity(1)['iron-plate']==base_capacity+1000,
    'Foreign-to-player transition must reset the counter baseline and include capacity')
  e.products_finished=101;advance();assert(total()==crafts+1)
  e.force=foreign;e.products_finished=151
  assert(Sm.capacity(1)['iron-plate']==base_capacity and Sm.machine_counts(1)['iron-plate']==base_count,
    'Capacity/counts must exclude a force change before its next sampled visit')
  advance();assert(total()==crafts+1)
  e.force=canonical;e.products_finished=201;advance()
  assert(total()==crafts+1,'Foreign interval was counted after returning to player ownership')
  e.products_finished=202;advance();assert(total()==crafts+2)
  e.valid=false;advance();assert(storage.machines[unit]==nil)
  local original_print=p.print;local notice
  p.print=function(value)notice=value end
  UI.open(p);p.force=foreign
  handlers.on_player_changed_force{player_index=p.index,force=canonical}
  assert(not UI.is_open(p) and p.gui.top.ssk_toggle.enabled==false,
    'Changing player force must close and disable the unsupported chart')
  UI.open(p)
  assert(not UI.is_open(p) and notice[1]=='production-flow.ui-player-force-only',
    'Commands must explain the supported force rather than showing mixed data')
  p.force=canonical;handlers.on_player_changed_force{player_index=p.index,force=foreign}
  assert(p.gui.top.ssk_toggle.enabled==true)
  p.print=original_print;UI.open(p)
  print('FORCE SCOPE OK: foreign candidates, both ownership transitions, capacity, crafts and player UI guard')
end
