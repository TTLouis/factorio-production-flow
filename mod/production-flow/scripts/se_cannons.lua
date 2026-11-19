-- Delivery cannon shipments for SE 0.7.64, observed through additive
-- prototype markers only (see data-final-fixes.lua):
--   beam       created right after SE takes one package from output slot 1
--   projectile created on the target surface 100 tiles above the target,
--              right after the beam unless meteor defence destroyed the shot
--   impact     the capsule explosion SE creates only when a payload spills
-- SE lands each payload exactly 120 ticks after firing. A paired shot with no
-- impact marker by then was inserted whole into the target delivery chest.
-- Inventory/configuration snapshots remain separate from dispatch and receipt
-- quantities throughout this provider.
local Sampler=require("scripts.sampler")
local Endpoints=require("scripts.transfer_endpoints")
local C={}
C.EFFECT_ID="production-flow-se-cannon-dispatch"
C.PROJECTILE_EFFECT_ID="production-flow-se-cannon-projectile"
C.IMPACT_EFFECT_ID="production-flow-se-cannon-impact"
C.SUPPORTED_VERSION="0.7.64"
local LIMIT,DISCOVERY_LIMIT=4096,256
local RETENTION=Sampler.PERIODS[#Sampler.PERIODS]*60
local CANNON,RECEIVER="se-delivery-cannon","se-delivery-cannon-chest"
local BEAM="se-delivery-cannon-beam"
local PROJECTILE="se-delivery-cannon-capsule-artillery-projectile"
local IMPACT="se-delivery-cannon-capsule-explosion"
local FALL_ALTITUDE,FALL_TIME=100,120
local MATCH_RADIUS=0.5

function C.available()
  local active_mods=script and script.active_mods
  return active_mods and active_mods["space-exploration"]==C.SUPPORTED_VERSION
    and type(defines.events.on_script_trigger_effect)=="number"
end

local function capabilities()
  local available=C.available()
  return {firing_effects=available,sent_manifest=available,received_manifest=available,
    destination=available,inventory_snapshots=available}
end

function C.init(tick)
  if not storage.se_cannons then
    storage.se_cannons={version=1,history={},first=1,count=0,serial=0,start_tick=tick,dropped={},in_flight={}}
  end
  storage.se_cannons.in_flight=storage.se_cannons.in_flight or {}
  return storage.se_cannons
end

local function remove_first(s,overflow)
  local record=s.history[s.first]
  s.history[s.first]=nil
  s.first=s.first%LIMIT+1;s.count=s.count-1
  if s.in_flight then s.in_flight[record.id]=nil end
  if s.last_beam and s.last_beam.record==record then s.last_beam=nil end
  local force=record.sender.force
  if overflow and force.valid then s.dropped[force.index]={force=force,tick=record.tick} end
end

function C.prune(tick)
  local s=storage.se_cannons
  if not s then return end
  while s.count>0 and s.history[s.first].tick<tick-RETENTION do remove_first(s) end
  for id,v in pairs(s.dropped) do
    if not v.force.valid or v.tick<tick-RETENTION then s.dropped[id]=nil end
  end
end

local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end

local package_payload
local function payload_map()
  if package_payload then return package_payload end
  package_payload={}
  for name,recipe in pairs(prototypes.recipe) do
    if name:find("se-delivery-cannon-pack-",1,true)==1 then
      local material,count,valid=nil,0,true
      for _,i in pairs(recipe.ingredients) do
        if i.name~="se-delivery-cannon-capsule" then
          if material or (i.type and i.type~="item") or not finite(i.amount) or i.amount<=0 then valid=false end
          material=i.name;count=i.amount
        end
      end
      local product=recipe.products[1]
      if valid and material and product and product.name then
        local prior=package_payload[product.name]
        if prior==nil then package_payload[product.name]={name=material,count_per_package=count}
        elseif not prior or prior.name~=material or prior.count_per_package~=count then package_payload[product.name]=false end
      elseif product and product.name then
        package_payload[product.name]=false
      end
    end
  end
  return package_payload
end

local function quality_name(q)
  if q and type(q)~="string" then q=q.name end
  return q or "normal"
end

-- The fired package is the one SE just took from output slot 1. When that
-- emptied the slot, the current recipe names it: the cannon has no module
-- slots, and a recipe change moves output items out of the machine.
local function fired_payload(cannon)
  local package,quality
  local ok=pcall(function()
    local inventory=cannon.get_inventory(defines.inventory.crafter_output)
    local stack=inventory and inventory.valid and inventory[1]
    if stack and stack.valid_for_read then package,quality=stack.name,quality_name(stack.quality) end
  end)
  if not ok then package=nil end
  if not package then
    ok=pcall(function()
      local recipe,recipe_quality=cannon.get_recipe()
      local product=recipe and recipe.products and recipe.products[1]
      if product and product.name then package,quality=product.name,quality_name(recipe_quality) end
    end)
    if not ok then return nil end
  end
  local payload=package and payload_map()[package]
  if not payload then return nil end
  return {{name=payload.name,quality=quality,count=payload.count_per_package}},package
end

-- Cannon routes share SE zone identities with rocket routes. A cached entry
-- is reused only for the same surface object, never for a reused index.
local zone_cache={}
local function zone_of(surface)
  local cached=zone_cache[surface.index]
  if cached and cached.surface==surface then return cached.zone,cached.name end
  local zone,name
  local api=remote and remote.interfaces and remote.interfaces["space-exploration"]
  if api and api.get_zone_from_surface_index then
    local ok,value=pcall(remote.call,"space-exploration","get_zone_from_surface_index",{surface_index=surface.index})
    if ok and type(value)=="table" and type(value.index)=="number" then zone,name=value.index,value.name end
  end
  zone_cache[surface.index]={surface=surface,zone=zone,name=name}
  return zone,name
end

local function named(entity,name,surface)
  return entity and entity.valid and entity.name==name and entity.surface==surface and entity or nil
end

local function effect_position(e,name,surface)
  local entity=named(e.source_entity,name,surface) or named(e.target_entity,name,surface)
  local p=entity and entity.position or e.source_position or e.target_position
  if not p then return nil end
  local x,y=p.x or p[1],p.y or p[2]
  if finite(x) and finite(y) then return {x=x,y=y} end
end

-- Pair the projectile with the beam raised immediately before it in the same
-- tick. Anything else (no beam, stale beam, other force) stays unpaired.
local function on_projectile(e,surface,s)
  local last=s.last_beam
  s.last_beam=nil
  if not (last and last.tick==e.tick and last.record.destination==nil) then return end
  local r=last.record
  local projectile=named(e.source_entity,PROJECTILE,surface) or named(e.target_entity,PROJECTILE,surface)
  if projectile and projectile.force~=r.sender.force then return end
  local p=effect_position(e,PROJECTILE,surface)
  if not p then return end
  local zone,zone_name=zone_of(surface)
  r.destination={surface=surface,zone=zone,name=zone_name or surface.name,position={x=p.x,y=p.y+FALL_ALTITUDE}}
  if not r.sender.zone then r.sender.zone=zone_of(r.sender.surface) end
  r.eta=e.tick+FALL_TIME
  r.status="in-flight"
  s.in_flight[r.id]=r
end

local function on_impact(e,surface,s)
  local p=effect_position(e,IMPACT,surface)
  if not p then return end
  for _,r in pairs(s.in_flight) do
    local d=r.destination
    if d.surface==surface and r.eta<=e.tick and (d.position.x-p.x)^2+(d.position.y-p.y)^2<=MATCH_RADIUS^2 then
      -- Same-target landings in one tick cannot be told apart: mark each.
      r.spilled=true
    end
  end
end

function C.on_effect(e)
  local id=e.effect_id
  if not (id==C.EFFECT_ID or id==C.PROJECTILE_EFFECT_ID or id==C.IMPACT_EFFECT_ID) then return end
  if not C.available() or e.tick~=game.tick then return end
  local surface=game.surfaces[e.surface_index]
  if not (surface and surface.valid) then return end
  if id~=C.EFFECT_ID then
    local s=storage.se_cannons
    if not s then return end
    s.in_flight=s.in_flight or {}
    if id==C.PROJECTILE_EFFECT_ID then on_projectile(e,surface,s) else on_impact(e,surface,s) end
    return
  end
  local p=effect_position(e,BEAM,surface)
  if not p then return end
  local x,y=p.x,p.y
  -- SE 0.7.64 creates the logistic firing explosion at cannon + {-0.5,-5}.
  -- Do not use a nearest entity guess or an unknown beam/weapon offset.
  local matches=surface.find_entities_filtered{name=CANNON,position={x=x+0.5,y=y+5},radius=0.05,limit=2}
  if #matches~=1 then return end
  local cannon=matches[1]
  if not (cannon.valid and cannon.name==CANNON and cannon.surface==surface and cannon.force.valid) then return end
  local sender=Endpoints.snapshot(cannon,"delivery-cannon")
  if not sender then return end
  local sent,package=fired_payload(cannon)
  local s=C.init(e.tick)
  if e.tick<s.start_tick then return end
  C.prune(game.tick)
  if s.count==LIMIT then remove_first(s,true) end
  s.serial=s.serial+1
  local observation={id=s.serial,tick=e.tick,kind="cannon_firing_effect",shot_count=1,sender=sender,
    sent=sent,package=package,received=nil,destination=nil,status="firing-observed"}
  s.history[(s.first-1+s.count)%LIMIT+1]=observation
  s.count=s.count+1
  s.last_beam={tick=e.tick,record=observation}
end

local function copy_manifest(items)
  if not items then return nil end
  local out={}
  for i,v in ipairs(items) do out[i]={name=v.name,quality=v.quality,count=v.count} end
  return out
end

-- Settle each paired shot one tick after SE lands it, so an impact marker
-- raised during the landing tick has always been seen first.
function C.on_tick(tick)
  local s=storage.se_cannons
  local in_flight=s and s.in_flight
  if not (in_flight and next(in_flight)) then return end
  for id,r in pairs(in_flight) do
    if tick>r.eta then
      in_flight[id]=nil
      local d=r.destination
      r.landed_tick=r.eta
      if r.spilled then
        r.status="spilled"
      elseif not d.surface.valid then
        r.status="lost"
      else
        -- The same lookup SE uses to choose the chest it inserts into.
        local ok,chests=pcall(function()
          return d.surface.find_entities_filtered{name=RECEIVER,position=d.position,limit=1}
        end)
        local chest=ok and chests and chests[1]
        if chest and chest.valid and r.sent then
          r.received=copy_manifest(r.sent)
          r.arrival_tick=r.eta
          r.receiver=Endpoints.snapshot(chest,"delivery-cannon-receiver",d.zone)
          r.status="received"
        else
          r.status="arrived"
        end
      end
    end
  end
end

function C.query(force,surface,tick,seconds)
  local result={observations={},shot_count=0,sent=nil,received=nil,destination=nil,
    seconds=0,truncated=false,capabilities=capabilities()}
  local s=storage.se_cannons
  if not (s and force and force.valid and surface and surface.valid) then return result end
  local since=math.max(s.start_tick,tick-math.min(math.max(seconds,0)*60,RETENTION))
  result.seconds=math.max(0,(tick-since)/60)
  local dropped=s.dropped[force.index]
  result.truncated=dropped and dropped.force==force and dropped.tick>=since or false
  for i=s.count-1,0,-1 do
    local r=s.history[(s.first-1+i)%LIMIT+1]
    local d=r.destination
    if r.sender.force==force and (r.sender.surface==surface or d and d.surface==surface)
      and r.tick>=since and r.tick<=tick then
      result.observations[#result.observations+1]=r
      result.shot_count=result.shot_count+1
    end
  end
  return result
end

local function inventory_contents(entity,id)
  local inv=entity.get_inventory(id)
  if not (inv and inv.valid) then return nil end
  local result={}
  for _,stack in pairs(inv.get_contents()) do
    local q=stack.quality
    if q and type(q)~="string" then q=q.name end
    result[#result+1]={name=stack.name,count=stack.count,quality=q or "normal"}
  end
  table.sort(result,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.quality<b.quality end)
  return result
end

-- On-demand endpoint/current-inventory discovery only. Neither stored items,
-- packed output nor the configured recipe establishes what has been sent or
-- received. One extra candidate discloses the bounded result's truncation.
function C.discover(surface,force)
  local result={cannons={},receivers={},truncated=false,observed_tick=game.tick,
    inventory_kind="current_contents",capabilities=capabilities()}
  if not (C.available() and surface and surface.valid and force and force.valid) then return result end
  local names={}
  for _,name in ipairs({CANNON,RECEIVER}) do
    if not prototypes.entity or prototypes.entity[name] then names[#names+1]=name end
  end
  if #names==0 then return result end
  local found=surface.find_entities_filtered{name=names,force=force,limit=DISCOVERY_LIMIT+1}
  result.truncated=#found>DISCOVERY_LIMIT
  local mapping=payload_map()
  for i=1,math.min(#found,DISCOVERY_LIMIT) do
    local e=found[i]
    if e.valid and e.force==force and e.surface==surface then
      local endpoint=Endpoints.snapshot(e,e.name==CANNON and "delivery-cannon" or "delivery-cannon-receiver")
      if endpoint and e.name==CANNON then
        local packages=inventory_contents(e,defines.inventory.crafter_output)
        local entry={endpoint=endpoint,ready_packages=packages,ready_payload=nil,declared_payload=nil,sent=nil,received=nil}
        local ready,known={},packages~=nil
        for _,p in ipairs(packages or {}) do
          local payload=mapping[p.name]
          if payload then
            ready[#ready+1]={name=payload.name,count=payload.count_per_package*p.count,
              quality=p.quality,package=p.name,packages=p.count}
          else known=false end
        end
        if known then entry.ready_payload=ready end
        local recipe=e.get_recipe()
        local prototype=recipe and prototypes.recipe[recipe.name]
        local payload=prototype and prototype.products[1] and mapping[prototype.products[1].name]
        if payload then entry.declared_payload={name=payload.name,count_per_package=payload.count_per_package} end
        result.cannons[#result.cannons+1]=entry
      elseif endpoint and e.name==RECEIVER then
        result.receivers[#result.receivers+1]={endpoint=endpoint,stored_items=inventory_contents(e,defines.inventory.chest),received=nil}
      end
    end
  end
  for _,list in ipairs({result.cannons,result.receivers}) do
    table.sort(list,function(a,b) return a.endpoint.unit_number<b.endpoint.unit_number end)
  end
  return result
end

return C
