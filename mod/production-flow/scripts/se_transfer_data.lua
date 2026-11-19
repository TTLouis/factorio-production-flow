-- Presentation-only SE transport queries. The providers own observation and
-- retention; this layer never reads another mod's private state or stock.
local Rockets=require("scripts.se_rockets")
local Cannons=require("scripts.se_cannons")
local Sampler=require("scripts.sampler")
local D={}
local RETENTION=Sampler.PERIODS[#Sampler.PERIODS]

local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end

local function copy_table(source)
  if not source then return nil end
  local out={}
  for k,v in pairs(source) do out[k]=v end
  if source.position then
    out.position={x=source.position.x or source.position[1],y=source.position.y or source.position[2]}
  end
  return out
end

local function copy_manifest(source,filters)
  if source==nil then return nil end
  local out={}
  for _,item in ipairs(source) do
    local quality=item.quality or "normal"
    if type(quality)~="string" then quality=quality.name end
    if (not filters.material or item.name==filters.material)
      and (not filters.quality or quality==filters.quality) then
      out[#out+1]={name=item.name,quality=quality,count=item.count}
    end
  end
  return out
end

local function copy_record(record,filters)
  local out=copy_table(record)
  out.from=copy_table(record.from)
  out.to=copy_table(record.to)
  out.remote=copy_table(record.remote)
  out.sender=copy_table(record.sender)
  out.receiver=copy_table(record.receiver)
  out.sent=copy_manifest(record.sent,filters)
  out.received=copy_manifest(record.received,filters)
  return out
end

local function boundary_tick(record,timing)
  if timing=="arrival" then
    -- An endpoint/arrival notification alone is not receipt quantity evidence.
    return record.received~=nil and record.arrival_tick or nil
  end
  return record.tick
end

local function in_range(tick,first,last,last_exclusive)
  return finite(tick) and (not first or tick>=first)
    and (not last or (last_exclusive and tick<last or not last_exclusive and tick<=last))
end

-- Default timing is departure. History may request "either" and then plot
-- each independently observed boundary. Bucket intervals are half-open.
function D.filter(records,filters)
  filters=filters or {}
  local out={}
  local first,last=filters.from_tick,filters.to_tick
  local bucket=filters.bucket
  local bucket_ticks=filters.bucket_ticks or 60
  if bucket~=nil and (not finite(bucket) or not finite(bucket_ticks) or bucket_ticks<=0) then return out end
  local timing=filters.timing or "departure"
  if timing~="departure" and timing~="arrival" and timing~="either" then return out end
  local function matches_time(tick)
    return in_range(tick,first,last,false)
      and (bucket==nil or in_range(tick,bucket,bucket+bucket_ticks,true))
  end
  for _,record in ipairs(records or {}) do
    local matches=not filters.method or record.method==filters.method
    matches=matches and (not filters.direction or record.direction==filters.direction)
    matches=matches and (not filters.route or record.route_id==filters.route)
    local time=boundary_tick(record,timing)
    local time_matches=timing=="either"
      and (matches_time(record.tick) or matches_time(boundary_tick(record,"arrival")))
      or timing~="either" and matches_time(time)
    if matches and time_matches then
      local copy=copy_record(record,filters)
      local material_match=not (filters.material or filters.quality)
        or (copy.sent and #copy.sent>0) or (copy.received and #copy.received>0)
      if material_match then out[#out+1]=copy end
    end
  end
  table.sort(out,function(a,b)
    if a.tick~=b.tick then return a.tick>b.tick end
    return a.key<b.key
  end)
  return out
end

local function route_id(direction,endpoint)
  -- SE zones are the stable remote-world identity. Unknown-zone legacy data
  -- keeps the original endpoint label, rather than resolving a reused index.
  local id=endpoint.zone
  if id==nil then
    local name=endpoint.name or "?"
    id="endpoint:"..#name..":"..name
  end
  return direction..":"..tostring(id)
end

local function normalize_rocket(record,surface)
  local from=record.from and record.from.surface==surface
  local to=record.to and record.to.surface==surface
  if from==to then return nil end
  local direction=to and "imports" or "exports"
  local endpoint=to and record.from or record.to
  if not endpoint then return nil end
  return {key="rocket:"..record.id,id=record.id,method="rocket",direction=direction,
    route_id=route_id(direction,endpoint),remote=endpoint,from=record.from,to=record.to,
    tick=record.departure_tick,arrival_tick=record.arrival_tick,sent=record.sent,received=record.received,
    landed_tick=record.landed_tick,
    sender=record.sender,receiver=record.receiver,status=record.status or "unconfirmed",
    cargo_loss=record.cargo_loss,pad_miss=record.pad_miss}
end

local function normalize_cannon(record,surface)
  local d=record.destination
  if d and d.surface then
    -- A beam paired with its landing projectile names the target surface;
    -- the provider sets Received only for a whole insert into a chest.
    local from={surface=record.sender.surface,zone=record.sender.zone,
      name=record.sender.surface.valid and record.sender.surface.name or "?"}
    local to={surface=d.surface,zone=d.zone,name=d.name}
    local from_here,to_here=from.surface==surface,to.surface==surface
    if from_here==to_here then return nil end -- Includes same-surface deliveries.
    local direction=to_here and "imports" or "exports"
    local endpoint=to_here and from or to
    return {key="cannon:"..record.id,id=record.id,method="cannon",direction=direction,
      route_id=route_id(direction,endpoint),remote=endpoint,from=from,to=to,
      tick=record.tick,arrival_tick=record.arrival_tick,landed_tick=record.landed_tick,eta=record.eta,
      sent=record.sent,received=record.received,
      sender=record.sender,receiver=record.receiver,status=record.status or "in-flight",
      unknown_payload=record.sent==nil,shot_count=record.shot_count or 1}
  end
  -- An unpaired firing effect proves a local cannon fired, not where it sent.
  return {key="cannon:"..record.id,id=record.id,method="cannon",direction="unpaired",
    route_id=nil,remote=nil,from={surface=record.sender.surface,zone=record.sender.zone,
      name=record.sender.surface.valid and record.sender.surface.name or "?"},to=nil,
    tick=record.tick,arrival_tick=nil,sent=nil,received=nil,sender=record.sender,receiver=nil,
    status="firing-observed",unknown_payload=true,shot_count=record.shot_count or 1}
end

local function accumulate(target,manifest)
  for _,item in ipairs(manifest or {}) do
    local quality=item.quality or "normal"
    local key=item.name.."/"..quality
    local value=target[key]
    if not value then value={name=item.name,quality=quality,count=0};target[key]=value end
    value.count=value.count+item.count
  end
end

local function array(totals)
  local result={}
  for _,value in pairs(totals) do result[#result+1]=value end
  table.sort(result,function(a,b)
    if a.name~=b.name then return a.name<b.name end
    return a.quality<b.quality
  end)
  return result
end

local function aggregation(id)
  return {id=id,records={},shipments=0,count=0,sent_complete=true,received_complete=true,_sent={},_received={}}
end

local function add(aggregate,record)
  aggregate.records[#aggregate.records+1]=record
  aggregate.shipments=aggregate.shipments+1
  aggregate.count=aggregate.shipments
  aggregate.sent_complete=aggregate.sent_complete and record.sent~=nil
  aggregate.received_complete=aggregate.received_complete and record.received~=nil
  accumulate(aggregate._sent,record.sent)
  accumulate(aggregate._received,record.received)
end

local function finish(aggregate)
  aggregate.sent_observed=array(aggregate._sent)
  aggregate.received_observed=array(aggregate._received)
  aggregate.sent=aggregate.sent_complete and aggregate.sent_observed or nil
  aggregate.received=aggregate.received_complete and aggregate.received_observed or nil
  aggregate._sent,aggregate._received=nil,nil
end

local function grouped(records)
  local result={imports={},exports={}}
  local index={}
  for _,record in ipairs(records) do
    if record.route_id and result[record.direction] then
      local group=index[record.route_id]
      if not group then
        group=aggregation(record.route_id)
        group.route_id=record.route_id
        group.direction=record.direction
        group.remote=copy_table(record.remote)
        group.endpoint=group.remote
        group.methods={}
        group._methods={}
        index[record.route_id]=group
        result[record.direction][#result[record.direction]+1]=group
      end
      add(group,record)
      local method=group._methods[record.method]
      if not method then
        method=aggregation(group.id..":"..record.method)
        method.method=record.method
        method.route_id=group.id
        group._methods[record.method]=method
        group.methods[#group.methods+1]=method
      end
      add(method,record)
    end
  end
  for _,direction in ipairs({"imports","exports"}) do
    table.sort(result[direction],function(a,b)
      local left,right=a.remote.name or "",b.remote.name or ""
      if left~=right then return left<right end
      return a.id<b.id
    end)
    for _,group in ipairs(result[direction]) do
      finish(group)
      for _,method in ipairs(group.methods) do finish(method) end
      table.sort(group.methods,function(a,b) return a.method<b.method end)
      group._methods=nil
    end
  end
  return result
end

function D.query(force,surface,tick,seconds,filters)
  filters=filters or {}
  local result={records={},groups={imports={},exports={}},materials={},qualities={},unpaired={},
    from_tick=0,to_tick=finite(tick) and tick or 0,seconds=0,truncated=false,coverage={rocket=0,cannon=0}}
  if not (force and force.valid and surface and surface.valid and finite(tick) and tick>=0
    and finite(seconds) and seconds>=0) then return result end
  result.from_tick=math.max(0,tick-math.min(seconds,RETENTION)*60)
  result.seconds=(tick-result.from_tick)/60
  -- Request the retained provider horizon before applying boundary timing.
  -- A received shipment may have departed before the chosen arrival window.
  local rockets=Rockets.query(force,surface,tick,RETENTION)
  local cannons=Cannons.query(force,surface,tick,RETENTION)
  result.coverage.rocket=math.min(result.seconds,rockets.seconds or 0)
  result.coverage.cannon=math.min(result.seconds,cannons.seconds or 0)
  result.truncated=(filters.method~="cannon" and rockets.truncated)
    or (filters.method~="rocket" and cannons.truncated) or false
  local raw={}
  for _,record in ipairs(rockets.records or {}) do
    if record.force==force and record.force.valid then
      local normalized=normalize_rocket(record,surface)
      if normalized then raw[#raw+1]=normalized end
    end
  end
  for _,record in ipairs(cannons.observations or {}) do
    local d=record.destination
    if record.sender and record.sender.force==force
      and (record.sender.surface==surface or d and d.surface==surface) then
      local normalized=normalize_cannon(record,surface)
      if normalized then raw[#raw+1]=normalized end
    end
  end
  local window=copy_table(filters)
  window.from_tick,window.to_tick=result.from_tick,result.to_tick
  result.records=D.filter(raw,window)
  result.groups=grouped(result.records)
  for _,record in ipairs(result.records) do
    if record.direction=="unpaired" then result.unpaired[#result.unpaired+1]=record end
  end
  -- Keep choice IDs independent of the active item/method/direction filter.
  local all=D.filter(raw,{from_tick=result.from_tick,to_tick=result.to_tick,timing=filters.timing})
  local materials,qualities={},{}
  for _,record in ipairs(all) do
    for _,manifest in pairs({sent=record.sent,received=record.received}) do
      for _,item in ipairs(manifest) do materials[item.name]=true;qualities[item.quality]=true end
    end
  end
  for value in pairs(materials) do result.materials[#result.materials+1]=value end
  for value in pairs(qualities) do result.qualities[#result.qualities+1]=value end
  table.sort(result.materials);table.sort(result.qualities)
  return result
end

return D
