-- Cargo-loss model checked against Space Exploration 0.7.64. Read only its
-- public zone and research interfaces. Keep unknown versions on dispatch counts.
local M={}
local MOD="space-exploration"
local CARGO_HAZARD={anomaly=1,["asteroid-field"]=.5,["asteroid-belt"]=.1}
local PAD_HAZARD={anomaly=.5,["asteroid-field"]=.1,["asteroid-belt"]=.05}

local function query(method,args)
  local api=remote and remote.interfaces and remote.interfaces[MOD]
  if not (api and api[method]) then return nil end
  local ok,value=pcall(remote.call,MOD,method,args)
  if ok then return value end
end

function M.zone(index)
  if type(index)~="number" then return nil end
  local value=query("get_zone_from_zone_index",{zone_index=index})
  if type(value)=="table" then return value end
end

local function navigation(zone,depth)
  if not zone or depth>5 then return nil end
  local position=zone.stellar_position
  local star,planet=zone.star_gravity_well or 0,zone.planet_gravity_well or 0
  if zone.type=="anomaly" then position={x=0,y=0} end
  if zone.type=="orbit" or not position then
    local parent=M.zone(zone.parent_index)
    local p=navigation(parent,depth+1)
    if not p then return nil end
    position=position or p.position
    if zone.type=="orbit" then
      star=p.star
      planet=parent.type=="star" and 0 or p.planet-(parent.type=="planet" and 1 or .5)
    end
  end
  if type(position)~="table" or type(position.x)~="number" or type(position.y)~="number"
    or type(star)~="number" or type(planet)~="number" then return nil end
  local distortion=zone.space_distortion or (zone.type=="anomaly" and 1 or 0)
  if type(distortion)~="number" then return nil end
  return {position=position,star=star,planet=planet,distortion=distortion}
end

local function travel_cost(a,b)
  if a.distortion>0 and b.distortion>0 then return 400*math.abs(a.distortion-b.distortion) end
  if a.distortion>0 then return 10000+500*b.star+100*b.planet end
  if b.distortion>0 then return 10000+500*a.star+100*a.planet end
  local x,y=a.position.x-b.position.x,a.position.y-b.position.y
  if x~=0 or y~=0 then
    return 400*math.sqrt(x*x+y*y)+500*(a.star+b.star)+100*(a.planet+b.planet)
  end
  if a.star==b.star then return 100*math.abs(a.planet-b.planet) end
  return 500*math.abs(a.star-b.star)+100*(a.planet+b.planet)
end

local function probability(value)
  return type(value)=="number" and value>=0 and value<=1
end

function M.snapshot(version,force,origin_index,destination_index,destination,targets_pad)
  if version~="0.7.64" or not destination then return nil end
  local delta=0
  if origin_index~=destination_index then
    local a,b=navigation(M.zone(origin_index),0),navigation(destination,0)
    if not (a and b) then return nil end
    delta=travel_cost(a,b)
  end
  if not (delta>=0 and delta<math.huge) then return nil end
  local cargo_modifier=query("get_cargo_loss",{force=force})
  local pad_modifier=targets_pad and query("get_survivability_loss",{force=force}) or nil
  if not probability(cargo_modifier) or (targets_pad and not probability(pad_modifier)) then return nil end
  local base=(delta+1000)/(delta+101000)
  local loss=(base+(1-base)*(CARGO_HAZARD[destination.type] or 0))*cargo_modifier
  local miss=targets_pad and (base+(1-base)*(PAD_HAZARD[destination.type] or 0))*pad_modifier or 1
  return loss,miss
end

local function expected_lost(count,loss)
  -- SE floors a uniform draw and the inventory caps removal at its count.
  local range=2*count*loss
  if range<=1 then return 0 end
  if range>=count then return count-count*(count+1)/(2*range) end
  local k=math.floor(range)
  return (k*(k-1)/2+k*(range-k))/range
end

function M.expected(item,loss,miss)
  local prototype=prototypes.item[item.name]
  if not prototype then return nil end
  local count=item.count
  if count<=1 or prototype.stack_size<=1 then return count end
  local off_pad=expected_lost(count,loss)
  local on_pad=expected_lost(count,loss/2)
  return count-(off_pad*miss+on_pad*(1-miss))
end

return M
