-- Read-only exchange grouping. Never join shipments by time proximity.
local RocketLoss=require("scripts.se_rocket_loss")
local E = { SLOT = 24 }
function E.key(record, fallback)
  local a,b=record.from and record.from.id,record.to and record.to.id
  if record.exchange_id and a and b then
    a,b=tostring(a),tostring(b)
    if a>b then a,b=b,a end
    return record.exchange_id..":"..a..":"..b
  end
  return "shipment:"..tostring(record.key or record.shipment_id or fallback)
end
local function matches(item,material,quality)
  return (not material or item.name==material)
    and (not quality or quality=="all" or (item.quality or "normal")==quality)
end
function E.amount(items,material,quality)
  if items==nil then return nil end
  local total=0
  for _,item in ipairs(items) do
    if matches(item,material,quality) then
      total=total+item.count
    end
  end
  return total
end
local function expected_receipt(record,material,quality)
  if record.cargo_loss==nil or record.pad_miss==nil then return nil end
  local miss=record.status=="padless" and 1 or record.pad_miss
  local estimate=0
  for _,item in ipairs(record.sent) do
    if matches(item,material,quality) then
      local count=RocketLoss.expected(item,record.cargo_loss,miss)
      if not count then return nil end
      estimate=estimate+count
    end
  end
  return estimate
end
function E.boundary(record)
  if record.direction=="exports" then return record.tick,"sent",record.sent end
  if record.direction=="imports" then return record.received~=nil and record.arrival_tick or nil,"received",record.received end
  return record.tick,"unknown",nil
end
function E.observation(record,material,quality)
  local tick,kind,items=E.boundary(record)
  if kind=="received" and not tick then
    local dispatch=E.amount(record.sent,material,quality)
    if dispatch and dispatch>0 and record.method=="rocket" then
      local estimate=expected_receipt(record,material,quality)
      if estimate then return record.tick,"inbound_estimate",estimate,dispatch end
    end
    -- An SE landing known not to be a measured whole receipt (spill, off-pad,
    -- missing chest/pad confirmation, deleted target) has no quantity to draw:
    -- showing the dispatch would read as a full delivery.
    if (dispatch==nil or dispatch>0) and (record.method=="rocket" or record.method=="cannon")
      and (record.landed_tick or record.status=="spilled" or record.status=="padless" or record.status=="lost") then
      return record.tick,"received",nil
    end
    return record.tick,"inbound_dispatch",dispatch and dispatch>0 and dispatch or nil
  end
  return tick,kind,E.amount(items,material,quality)
end
function E.add_observation(group,kind,count,dispatch)
  if count then
    group[kind]=(group[kind] or 0)+count
    group[kind.."_known"]=true
  else
    group.unmeasured=true
  end
  if dispatch then group.estimated_dispatch=(group.estimated_dispatch or 0)+dispatch end
  if count==nil or kind=="inbound_dispatch" or kind=="inbound_estimate" then group.unknown=true end
end
function E.build(records,first,last,material,quality)
  local groups,index={},{}
  for i,record in ipairs(records or {}) do
    local tick,kind,count,dispatch=E.observation(record,material,quality)
    if tick and tick>=first and tick<=last and (count==nil or count>0) then
      local key=E.key(record,i)
      local group=index[key]
      if not group then
        group={key=key,first_tick=tick,last_tick=tick,sent=0,received=0,records={},unknown=false}
        index[key]=group;groups[#groups+1]=group
      end
      group.first_tick=math.min(group.first_tick,tick);group.last_tick=math.max(group.last_tick,tick)
      group.records[record.key or tostring(i)]=true
      E.add_observation(group,kind,count,dispatch)
    end
  end
  table.sort(groups,function(a,b) if a.first_tick~=b.first_tick then return a.first_tick<b.first_tick end;return a.key<b.key end)
  return groups
end
function E.page(groups,width,requested)
  local capacity=math.max(1,math.floor(width/E.SLOT))
  local pages=math.max(1,math.ceil(#groups/capacity))
  local page=math.max(1,math.min(requested or pages,pages))
  return page,pages,(page-1)*capacity+1,math.min(page*capacity,#groups)
end
return E
