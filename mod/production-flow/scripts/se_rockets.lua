-- SE's public launch contract supplies sent cargo, not received cargo. Keep
-- this ledger separate from Space Age's confirmed-arrival history.
-- For SE 0.7.64 only, the in-flight cargo is also read from the script
-- inventory SE creates at launch (LuaGameScript::get_script_inventories).
-- SE removes lost items from that inventory during transition and moves the
-- remainder into the landing pad before destroying it six seconds later.
local Sampler = require("scripts.sampler")
local Endpoints = require("scripts.transfer_endpoints")
local RocketLoss = require("scripts.se_rocket_loss")
local R = {}
local LIMIT = 4096
local MOD = "space-exploration"
local CARGO_VERSION = "0.7.64"
-- Refresh well inside SE's 360-tick descent so the last read follows losses.
local CARGO_REFRESH = 30
local CARGO_STALE = 300
local RETENTION = Sampler.PERIODS[#Sampler.PERIODS] * 60

function R.available()
  return script and script.active_mods and script.active_mods["space-exploration"] ~= nil
    and type(defines.events.se_on_cargo_rocket_launched) == "number"
end

function R.init(tick)
  if not storage.se_rockets then
    storage.se_rockets = {version=1, history={}, first=1, count=0, seen={}, serial=0,
      start_tick=tick, dropped={}, tracking={}}
  end
  storage.se_rockets.tracking=storage.se_rockets.tracking or {}
  return storage.se_rockets
end

local function remove_first(s, overflow)
  local record=s.history[s.first]
  s.history[s.first]=nil
  s.first=s.first%LIMIT+1
  s.count=s.count-1
  s.seen[record.key]=nil
  if s.tracking then s.tracking[record.id]=nil end
  if overflow and record.force.valid then s.dropped[record.force.index]={force=record.force,tick=record.departure_tick} end
end

function R.prune(tick)
  local s=storage.se_rockets
  if not s then return end
  while s.count>0 and s.history[s.first].departure_tick<tick-RETENTION do remove_first(s) end
  for id,v in pairs(s.dropped) do if not v.force.valid or v.tick<tick-RETENTION then s.dropped[id]=nil end end
end

local function endpoint(surface, zone, name)
  return {surface=surface, zone=zone, name=name or (surface and surface.name) or "?"}
end

local function manifest(stacks)
  if type(stacks)~="table" then return nil end
  local items, by_key={},{}
  local n=0
  for _,stack in pairs(stacks) do
    n=n+1
    if n>1024 or type(stack)~="table" or type(stack.name)~="string" or not prototypes.item[stack.name]
      or type(stack.count)~="number" or stack.count<=0 or stack.count~=stack.count or stack.count==math.huge then return nil end
    local quality=stack.quality
    if quality and type(quality)~="string" then quality=quality.name end
    quality=quality or "normal"
    local key=stack.name.."/"..quality
    if not by_key[key] then by_key[key]={name=stack.name,quality=quality,count=0};items[#items+1]=by_key[key] end
    by_key[key].count=by_key[key].count+stack.count
  end
  table.sort(items,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.quality<b.quality end)
  return #items>0 and items or nil
end

local function contents(inventory)
  local ok,list=pcall(function() return inventory.get_contents() end)
  if not ok or type(list)~="table" then return nil end
  if next(list)==nil then return {} end
  return manifest(list)
end

local function same(a,b)
  if not (a and b) or #a~=#b then return false end
  for i=1,#a do
    if a[i].name~=b[i].name or a[i].quality~=b[i].quality or a[i].count~=b[i].count then return false end
  end
  return true
end

-- Claim the one unclaimed SE script inventory holding exactly the launched
-- manifest. Several identical candidates are ambiguous: leave Received unknown.
local function cargo_inventory(s,items)
  if script.active_mods[MOD]~=CARGO_VERSION then return nil end
  local ok,all=pcall(function() return game.get_script_inventories(MOD) end)
  local list=ok and type(all)=="table" and all[MOD]
  if type(list)~="table" then return nil end
  local claimed={}
  for _,r in pairs(s.tracking) do
    if r.cargo_inventory then claimed[r.cargo_inventory]=true end
  end
  local expected_total=0
  for _,v in ipairs(items) do expected_total=expected_total+v.count end
  local found
  for _,inventory in pairs(list) do
    if inventory.valid and not claimed[inventory] then
      local count_fn=inventory.get_item_count
      if not count_fn or count_fn()==expected_total then
        if same(contents(inventory),items) then
          if found then return nil end
          found=inventory
        end
      end
    end
  end
  return found
end

function R.on_launch(e)
  if not R.available() then return end
  local pad=e.launchpad
  if not (pad and pad.valid and pad.name=="se-rocket-launch-pad" and pad.unit_number==e.unit_number
    and pad.force.valid and pad.force==game.forces[e.force_name] and pad.surface.valid) then return end
  local tick=e.tick
  if type(tick)~="number" or tick~=game.tick or type(e.destination_zone_index)~="number" then return end
  local items=manifest(e.launched_contents)
  if not items then return end
  local s=R.init(tick)
  if tick<s.start_tick then return end
  R.prune(game.tick)
  local key=e.unit_number..":"..tick
  if s.seen[key] then return end
  local landing=e.landing_pad
  if landing and (not landing.valid or landing.force~=pad.force) then return end
  local version=script.active_mods["space-exploration"]
  local zone=RocketLoss.zone(e.destination_zone_index)
  local destination=landing and landing.surface or zone and zone.surface_index and game.surfaces[zone.surface_index]
  if destination and not destination.valid then destination=nil end
  local cargo_loss,pad_miss=RocketLoss.snapshot(version,pad.force,e.zone_index,e.destination_zone_index,zone,landing~=nil)
  if s.count==LIMIT then remove_first(s,true) end
  s.serial=s.serial+1
  local record={id=s.serial,key=key,force=pad.force,departure_tick=tick,launch_pad=pad.unit_number,
    landing_pad=landing and landing.unit_number,landing_pad_name=e.landing_pad_name,
    from=endpoint(pad.surface,e.zone_index,e.zone_name),
    to=endpoint(destination,e.destination_zone_index,e.destination_zone_name),
    sender=Endpoints.snapshot(pad,"rocket_sender",e.zone_index),
    receiver=landing and Endpoints.snapshot(landing,"rocket_receiver",e.destination_zone_index),
    sent=items, received=nil, arrival_tick=nil, status="unconfirmed",cargo_loss=cargo_loss,pad_miss=pad_miss}
  s.history[(s.first-1+s.count)%LIMIT+1]=record
  s.count=s.count+1
  s.seen[key]=true
  local inventory=cargo_inventory(s,items)
  if inventory then
    record.cargo_inventory=inventory
    record.cargo=items
    record.cargo_tick=tick
    record.landing_entity=landing
    s.tracking[record.id]=record
  end
end

local function pad_holds(pad,items)
  local ok,inventory=pcall(function() return pad.get_inventory(defines.inventory.chest) end)
  if not (ok and inventory and inventory.valid) then return false end
  for _,item in ipairs(items) do
    local counted,count=pcall(function() return inventory.get_item_count({name=item.name,quality=item.quality}) end)
    if not counted or type(count)~="number" or count<item.count then return false end
  end
  return true
end

-- SE 0.7.64 lands cargo in this same tick, before this handler (Production
-- Flow loads after SE). Into an empty pad it transfers each launched stack to
-- its slot; into an occupied one it inserts each stack and destroys whatever
-- did not fit. The pad has 110 more slots than the launched inventory, so a
-- usable empty slot left after landing proves every launched stack went in
-- whole, whatever the pad held before. A pad without one stays unknown.
local function landed_whole(pad)
  local inventory=pad.get_inventory(defines.inventory.chest)
  return inventory~=nil and inventory.valid and inventory.count_empty_stacks(false,false)>0
end

-- SE destroys the cargo inventory only when the capsule lands. A pad landing
-- transfers the post-loss contents into the pad; an off-pad landing spreads
-- them over cargo pods, which is not a receipt at the targeted pad.
local function finish(r,tick)
  local cargo,pad=r.cargo,r.landing_entity
  r.cargo_inventory,r.landing_entity,r.cargo=nil,nil,nil
  r.landed_tick=tick
  if r.status~="unconfirmed" or not cargo or not r.cargo_tick or tick-r.cargo_tick>CARGO_STALE then return end
  if not (pad and pad.valid and pad.unit_number==r.landing_pad) then r.receipt="pad-unavailable";return end
  if not landed_whole(pad) then r.receipt="pad-full";return end
  -- On the landing tick the pad must hold at least the landed cargo. Fewer
  -- items means the pad was full or already emptied: keep Received unknown.
  if not pad_holds(pad,cargo) then r.receipt="pad-mismatch";return end
  r.received=cargo
  r.arrival_tick=tick
  r.status="received"
  r.receipt="pad"
end

function R.on_tick(tick)
  local s=storage.se_rockets
  local tracking=s and s.tracking
  if not (tracking and next(tracking)) then return end
  for id,r in pairs(tracking) do
    local inventory=r.cargo_inventory
    if inventory and inventory.valid then
      if (tick+id)%CARGO_REFRESH==0 then
        local cargo=contents(inventory)
        if cargo then r.cargo=cargo;r.cargo_tick=tick end
      end
    else
      tracking[id]=nil
      finish(r,tick)
    end
  end
end

function R.on_padless(e)
  local s=storage.se_rockets
  local pad=e.launchpad
  if not (s and pad and pad.valid and pad.force.valid) then return end
  local candidate
  for i=s.count-1,0,-1 do
    local r=s.history[(s.first-1+i)%LIMIT+1]
    if e.tick-r.departure_tick>36000 then break end
    if r.launch_pad==e.unit_number and r.force==pad.force and r.to.zone==e.destination_zone_index
      and r.status=="unconfirmed" and e.tick>=r.departure_tick then
      if candidate then return end -- The callback has no shipment ID; do not guess.
      candidate=r
    end
  end
  if candidate then candidate.status="padless";candidate.status_tick=e.tick end
end

local function each(s,fn)
  if s then for i=0,s.count-1 do fn(s.history[(s.first-1+i)%LIMIT+1]) end end
end

function R.surfaces(force)
  local result={}
  each(storage.se_rockets,function(r)
    if r.force==force then for _,e in ipairs({r.from,r.to}) do
      if e.surface and e.surface.valid then result[e.surface.index]=true end
    end end
  end)
  return result
end

-- Routes group remote surfaces, with individual pad/shipment details retained.
-- Received stays nil unless a pad landing was measured: zero would assert a receipt.
function R.query(force,surface,tick,seconds,material,options)
  local s=storage.se_rockets
  local result={imports={},exports={},materials={},records={},seconds=0,shipments=0}
  if not (s and surface and surface.valid) then return result end
  local since=math.max(s.start_tick,tick-math.min(seconds*60,RETENTION))
  result.seconds=math.max(0,(tick-since)/60)
  local dropped=s.dropped[force.index]
  result.truncated=dropped and dropped.force==force and dropped.tick>=since or false
  local raw_only=options and options.raw_only
  if raw_only then
    for i=s.count-1,0,-1 do
      local r=s.history[(s.first-1+i)%LIMIT+1]
      if r.departure_tick<since then break end
      if r.force==force and r.force.valid and r.departure_tick<=tick then
        local from=r.from.surface==surface
        local to=r.to.surface==surface
        if from~=to then
          result.shipments=result.shipments+1
          result.records[#result.records+1]=r
        end
      end
    end
    table.sort(result.records,function(a,b) return a.id>b.id end)
    return result
  end
  local groups={imports={},exports={}}
  local material_set={}
  each(s,function(r)
    if r.force~=force or not r.force.valid or r.departure_tick<since or r.departure_tick>tick then return end
    local from=r.from.surface==surface
    local to=r.to.surface==surface
    if from==to then return end -- Includes same-surface deliveries.
    local direction=to and "imports" or "exports"
    local remote_end=to and r.from or r.to
    local items={}
    for _,v in ipairs(r.sent) do
      material_set[v.name]=true
      if not material or v.name==material then items[#items+1]=v end
    end
    if #items==0 then return end
    local id=tostring(remote_end.zone or (remote_end.surface and remote_end.surface.index) or remote_end.name)
    local route=groups[direction][id]
    if not route then
      route={id=direction..":"..id,endpoint=remote_end,items={},by_key={},records={},shipments=0,received=nil}
      groups[direction][id]=route;result[direction][#result[direction]+1]=route
    end
    route.shipments=route.shipments+1
    route.records[#route.records+1]=r
    for _,v in ipairs(items) do
      local key=v.name.."/"..v.quality
      if not route.by_key[key] then route.by_key[key]={name=v.name,quality=v.quality,count=0};route.items[#route.items+1]=route.by_key[key] end
      route.by_key[key].count=route.by_key[key].count+v.count
    end
    result.shipments=result.shipments+1
    result.records[#result.records+1]=r
  end)
  for name in pairs(material_set) do result.materials[#result.materials+1]=name end
  table.sort(result.materials)
  for _,direction in ipairs({"imports","exports"}) do
    table.sort(result[direction],function(a,b) if a.endpoint.name~=b.endpoint.name then return a.endpoint.name<b.endpoint.name end;return a.id<b.id end)
    for _,r in ipairs(result[direction]) do
      table.sort(r.items,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.quality<b.quality end)
      r.by_key=nil
      table.sort(r.records,function(a,b) return a.id>b.id end)
    end
  end
  table.sort(result.records,function(a,b) return a.id>b.id end)
  return result
end

return R
