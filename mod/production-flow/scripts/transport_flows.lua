-- Read-only physical transport evidence. These measures never alter production
-- statistics, recipe models, stock scans, or another mod's private state.
local Transfers=require("scripts.transfers")
local Rockets=require("scripts.se_rockets")
local Data=require("scripts.se_transfer_data")
local Sampler=require("scripts.sampler")
local F={}
local RETENTION=Sampler.PERIODS[#Sampler.PERIODS]

local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function valid(force,surface,tick,seconds)
  return force and force.valid and surface and surface.valid and finite(tick) and tick>=0
    and finite(seconds) and seconds>=0
end
local function provider()
  if Transfers.available() then return "sa" end
  if Rockets.available() then return "se" end
end
local function inside(tick,first,last) return finite(tick) and tick>=first and tick<=last end
local function endpoint_direction(from,to,surface)
  local outgoing=from and from.surface==surface
  local incoming=to and to.surface==surface
  if outgoing==incoming then return nil end
  return incoming and "imports" or "exports"
end
local function contents(record)
  local result={}
  if record.contents then
    for _,item in ipairs(record.contents) do result[#result+1]={name=item.name,quality=item.quality,count=item.count} end
  else
    -- Old SA receipts preserved item totals, but not quality. Nil remains
    -- unknown here; all-quality chart totals can still use the observed count.
    for name,count in pairs(record.items or {}) do result[#result+1]={name=name,count=count} end
    table.sort(result,function(a,b)return a.name<b.name end)
  end
  return result
end
local function sa_records(boundaries,surface)
  local by_shipment,records={},{ }
  for _,boundary in ipairs(boundaries.records or {}) do
    local id=boundary.shipment_id
    local record=by_shipment[id]
    if not record then
      record={key="sa:"..id,id=id,method="cargo-pod",from=boundary.from,to=boundary.to,
        status="unconfirmed",quality_exact=true}
      by_shipment[id]=record;records[#records+1]=record
    end
    if boundary.to then record.to=boundary.to end
    record.sender=record.sender or boundary.sender
    record.receiver=record.receiver or boundary.receiver
    record.exchange_id=record.exchange_id or boundary.exchange_id
    record.quality_exact=record.quality_exact and boundary.quality_exact~=false
    if boundary.kind=="sent" then record.sent=contents(boundary);record.tick=boundary.tick;record.departure_known=true
    elseif boundary.kind=="received" then
      record.received=contents(boundary);record.arrival_tick=boundary.tick;record.status="received"
      record.legacy=boundary.legacy or nil
    end
  end
  local result={}
  for _,record in ipairs(records) do
    record.direction=endpoint_direction(record.from,record.to,surface)
    if record.direction then
      record.remote=record.direction=="imports" and record.from or record.to
      record.route_id=record.remote and record.direction..":"..record.remote.id or nil
      -- Legacy arrival history has no departure time. The sort/log fallback
      -- uses its real arrival, while a sent manifest remains explicitly nil.
      record.tick=record.tick or record.arrival_tick
      result[#result+1]=record
    end
  end
  return result
end
local function filter_sa(records,filters)
  local eligible={}
  for _,record in ipairs(records) do
    if not filters.quality or record.quality_exact~=false then eligible[#eligible+1]=record end
  end
  local result=Data.filter(eligible,filters)
  for _,record in ipairs(result) do
    if record.quality_exact==false then
      for _,manifest in pairs({sent=record.sent,received=record.received}) do
        for _,item in ipairs(manifest) do item.quality=nil end
      end
    end
  end
  return result
end

function F.history(force,surface,tick,seconds,filters)
  local empty={provider=nil,records={},materials={},qualities={},groups={imports={},exports={}},
    from_tick=0,to_tick=finite(tick) and tick or 0,seconds=0,period_seconds=0,truncated=false,coverage={}}
  if not valid(force,surface,tick,seconds) then return empty end
  local selected=provider()
  if not selected then return empty end
  local active={};for key,value in pairs(filters or {}) do active[key]=value end
  active.timing=active.timing or "either"
  if active.quality=="all" then active.quality=nil end
  if selected=="se" then
    local result=Data.query(force,surface,tick,seconds,active)
    result.provider="se";result.period_seconds=result.seconds
    return result
  end
  local first=math.max(0,tick-math.min(seconds,RETENTION)*60)
  local boundaries=Transfers.boundaries(force,surface,tick,seconds,{companions=true})
  local raw=sa_records(boundaries,surface)
  active.from_tick,active.to_tick=first,tick
  local coverage=boundaries.coverage or {}
  local result={provider="sa",records=filter_sa(raw,active),materials={},qualities={},
    groups={imports={},exports={}},from_tick=first,to_tick=tick,seconds=(tick-first)/60,
    period_seconds=(tick-first)/60,truncated=boundaries.dropped_tick and boundaries.dropped_tick>=first or false,
    coverage={sent=math.min((tick-first)/60,coverage.sent or boundaries.covered_seconds or 0),
      received=math.min((tick-first)/60,coverage.received or boundaries.covered_seconds or 0)},
    received_partial=boundaries.received_gap_tick and boundaries.received_gap_tick>=first or false,
    coverage_known=boundaries.coverage_known==true}
  if not active._skip_choices then
    local materials,qualities={},{ }
    for _,record in ipairs(filter_sa(raw,{from_tick=first,to_tick=tick,timing="either"})) do
      for _,manifest in pairs({sent=record.sent,received=record.received}) do
        for _,item in ipairs(manifest) do materials[item.name]=true;if item.quality then qualities[item.quality]=true end end
      end
    end
    for name in pairs(materials) do result.materials[#result.materials+1]=name end
    for name in pairs(qualities) do result.qualities[#result.qualities+1]=name end
    table.sort(result.materials);table.sort(result.qualities)
  end
  return result
end

local function direction(history,result,name)
  return {activity=false,sent=nil,received=nil,sent_rate=nil,received_rate=nil,
    sent_known=false,received_known=false,sent_partial=true,received_partial=true,
    history={provider=result.provider,surface_index=result.surface_index,material=name,direction=history},_methods={}}
end
local function material(result,name)
  local key="item/"..name
  local entry=result.materials[key]
  if not entry then
    entry={key=key,material=name,provider=result.provider,surface_index=result.surface_index}
    entry.imports=direction("imports",result,name);entry.exports=direction("exports",result,name)
    result.materials[key]=entry
  end
  return entry
end
local function manifest_totals(manifest)
  if manifest==nil then return nil end
  local totals={}
  for _,item in ipairs(manifest) do
    if type(item.name)=="string" and finite(item.count) and item.count>=0 then
      totals[item.name]=(totals[item.name] or 0)+item.count
    end
  end
  return totals
end
local function add_route(boundary,record)
  local remote=record.remote
  local surface=remote and remote.surface
  local id=(record.method or "unknown")..":"..tostring(record.route_id or remote and (remote.id or surface and surface.index or remote.name) or "unknown")
  boundary._routes=boundary._routes or {}
  if boundary._routes[id] then return end
  boundary._routes[id]=true
  boundary.routes=boundary.routes or {}
  boundary.routes[#boundary.routes+1]={method=record.method,
    remote_name=surface and surface.valid and (surface.localised_name or surface.name)
      or remote and (remote.name or remote.zone and remote.zone.name)}
end
local function add_event(result,record,kind,tick,manifest)
  for index,item in ipairs(manifest or {}) do
    if finite(item.count) and item.count>0 then
      local stats_included
      if result.provider=="se" and record.method=="rocket" and result._stats_excluded then stats_included=false end
      -- SE cannons: packing is an ordinary crafting recipe, so the sent plates
      -- are already in production statistics; the landing insert is not.
      if result.provider=="se" and record.method=="cannon" and result._stats_excluded then stats_included=kind=="sent" end
      -- Native 2.1.24 cargo-pod probes leave item production/consumption
      -- statistics unchanged at dispatch, landing and delivery.
      if result.provider=="sa" and result._stats_excluded then stats_included=false end
      result.events[#result.events+1]={key=record.key..":"..kind..":"..index,tick=tick,
        material="item/"..item.name,delta=(kind=="sent" and -1 or 1)*item.count,kind=kind,
        provider=result.provider,surface_index=result.surface_index,quality=item.quality,quality_exact=record.quality_exact~=false,
        stats_included=stats_included,
        method=record.method,shipment_id=record.id}
    end
  end
end

function F.query(force,surface,tick,seconds,options)
  local result={provider=nil,period_seconds=0,materials={},events={},coverage={},truncated=false,
    from_tick=0,to_tick=finite(tick) and tick or 0,scope_valid=false,unknown={}}
  if not valid(force,surface,tick,seconds) then return result end
  result.scope_valid=true;result.surface_index=surface.index
  local skip_events=options and options.skip_events
  local filter_material=options and options.material
  if filter_material and filter_material:sub(1,5)=="item/" then filter_material=filter_material:sub(6) end
  local history=F.history(force,surface,tick,seconds,{_skip_choices=true,_skip_groups=true,material=filter_material})
  result.provider=history.provider
  result.from_tick,result.to_tick,result.period_seconds=history.from_tick,history.to_tick,history.period_seconds
  result.coverage,result.truncated=history.coverage or {},history.truncated or false
  result.coverage_known=history.coverage_known==true
  result.received_partial=history.received_partial==true
  if not result.provider then return result end
  -- LuaBootstrap.active_mods returns a full table. Read it once per query,
  -- rather than marshalling every installed mod for every manifest stack.
  local active_mods=script.active_mods
  result._stats_excluded=result.provider=="se" and active_mods["space-exploration"]=="0.7.64"
    or result.provider=="sa" and active_mods["space-age"]=="2.1.24"
  result.unknown=result.provider=="se" and {cannon_payloads=true,rocket_receipts=true,spaceships=true,
    unpaired_cannon_observations=#(history.unpaired or {})} or {}
  local complete={}
  for _,kind in ipairs({"sent","received"}) do
    complete[kind]=result.provider=="sa" and result.coverage_known and not result.truncated
      and (result.coverage[kind] or 0)>=result.period_seconds and result.period_seconds>0
      and not (kind=="received" and result.received_partial)
  end
  for _,record in ipairs(history.records or {}) do
    if record.direction=="imports" or record.direction=="exports" then
      local sent=inside(record.tick,result.from_tick,result.to_tick) and manifest_totals(record.sent) or nil
      local received=inside(record.arrival_tick,result.from_tick,result.to_tick) and manifest_totals(record.received) or nil
      local names={}
      for name in pairs(sent or {}) do names[name]=true end
      for name in pairs(received or {}) do names[name]=true end
      for name in pairs(names) do
        local boundary=material(result,name)[record.direction]
        boundary.activity=true;boundary._methods[record.method]=true
        add_route(boundary,record)
        for _,kind in ipairs({"sent","received"}) do
          local totals
          if kind=="sent" then totals=sent else totals=received end
          if totals then
            boundary[kind]=(boundary[kind] or 0)+(totals[name] or 0)
            boundary[kind.."_known"]=true
          elseif kind=="sent" and record.sent==nil or kind=="received" and record.received==nil then
            boundary["_"..kind.."_unknown"]=true
          end
        end
      end
      if not skip_events then
        if record.direction=="exports" and sent then add_event(result,record,"sent",record.tick,record.sent) end
        if record.direction=="imports" and received then add_event(result,record,"received",record.arrival_tick,record.received) end
      end
    end
  end
  for _,entry in pairs(result.materials) do
    for _,side in ipairs({"imports","exports"}) do
      local boundary=entry[side]
      local methods={};for method in pairs(boundary._methods) do methods[#methods+1]=method end;table.sort(methods)
      boundary.methods=methods;boundary.history.method=#methods==1 and methods[1] or nil;boundary._methods=nil
      boundary._routes=nil
      for _,kind in ipairs({"sent","received"}) do
        -- SA's recording may be complete for observed boundary events, but an
        -- older receipt-only shipment still has no exact sent manifest.
        boundary[kind.."_partial"]=not complete[kind] or not boundary[kind.."_known"] or boundary["_"..kind.."_unknown"]==true
        boundary["_"..kind.."_unknown"]=nil
        if boundary[kind]~=nil and result.period_seconds>0 then boundary[kind.."_rate"]=boundary[kind]/result.period_seconds end
      end
    end
  end
  if not skip_events then
    table.sort(result.events,function(a,b)if a.tick~=b.tick then return a.tick<b.tick end;return a.key<b.key end)
  end
  result._stats_excluded=nil
  return result
end

function F.events(force,surface,tick,seconds,filters)
  local mat=filters and filters.material
  local result=F.query(force,surface,tick,seconds,mat and {material=mat} or nil)
  if mat then
    local key=mat:sub(1,5)=="item/" and mat or "item/"..mat
    local events={}
    for _,event in ipairs(result.events) do if event.material==key then events[#events+1]=event end end
    return events,result
  end
  return result.events,result
end
return F
