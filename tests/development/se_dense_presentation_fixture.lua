-- PRIVATE SYNTHETIC PRESENTATION INPUT. Never an SE observation provider.
-- Paired cannon payloads and receipt quantities below are deliberately made
-- up to exercise rendering. Install only for labelled native screenshots and
-- restore before saving. No shipment, stock or production storage is changed.
local Data=require("scripts.se_transfer_data")
local F={}
local active
local MATERIALS={"copper-plate","electronic-circuit","iron-plate","steel-plate"}
local REMOTES={
  {"nauvis-orbit","Nauvis Orbit","Synthetic Calidus Orbit"},
  {"tarn","Tarn","Synthetic Tarn"},
  {"aster","Aster","Synthetic Aster"},
  {"vulcanite","Vulcanite","Synthetic Vulcanite"},
  {"cryonite","Cryonite","Synthetic Cryonite"},
  {"vesta","Vesta","Synthetic Vesta"},
  {"juno","Juno","Synthetic Juno"},
}
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function copy(source)
  local out={};for k,v in pairs(source or {}) do out[k]=v end;return out
end
local function endpoint(surface,index)
  return {surface=surface,zone=900000+index,name=surface.name}
end
local function remote_surface(index)
  local names=REMOTES[index]
  for i=1,2 do
    local surface=game.get_surface(names[i])
    if surface and surface.valid and surface~=active.surface then return surface,false end
  end
  local surface=game.get_surface(names[3])
  if surface and surface.valid then return surface,false end
  return game.create_surface(names[3],{default_enable_all_autoplace_controls=false,
    autoplace_settings={entity={treat_missing_as_default=false,settings={}},
      decorative={treat_missing_as_default=false,settings={}}},peaceful_mode=true}),true
end
local function manifest(iron,secondary,count)
  return {{name="iron-plate",quality="normal",count=iron},
    {name=secondary,quality="normal",count=count}}
end
local function regenerate()
  local records={};local total=#active.remotes*16
  local span=math.min(36000,active.anchor)
  local first=active.anchor-span
  local ordinal=0
  for remote_index,remote in ipairs(active.remotes) do
    local other=endpoint(remote,remote_index)
    local here=endpoint(active.surface,0)
    for _,direction in ipairs({"imports","exports"}) do
      for _,method in ipairs({"rocket","cannon"}) do
        for shipment=1,4 do
          ordinal=ordinal+1
          -- Space observations over the available real game clock. Keep both
          -- boundaries strictly in the past, even on young fixture maps.
          local tick=math.floor(first+span*(ordinal-.5)/(total+1))
          local remaining=active.anchor-tick
          local travel=math.min(method=="rocket" and 1200 or 180,math.max(1,math.floor(remaining*.55)))
          local base=method=="rocket" and 600 or 80
          local sent=base+remote_index*110+shipment*65+(direction=="exports" and 200 or 0)
          local secondary=({"copper-plate","steel-plate","electronic-circuit"})[(shipment+remote_index-2)%3+1]
          local received=math.max(0,sent-(remote_index*17+shipment*9))
          local unknown=remote_index==3 and shipment==4
          local source=direction=="imports" and other or here
          local target=direction=="imports" and here or other
          records[#records+1]={key="synthetic:"..ordinal,id=ordinal,synthetic=true,
            fixture_kind="synthetic-presentation-only",method=method,direction=direction,
            route_id=direction..":"..other.zone,remote=other,from=source,to=target,
            tick=tick,arrival_tick=not unknown and math.min(active.anchor,tick+travel) or nil,
            sent=manifest(sent,secondary,shipment*40+remote_index*25),
            received=not unknown and manifest(received,secondary,shipment*35+remote_index*20) or nil,
            sender=nil,receiver=nil,status=unknown and "synthetic-receipt-unknown" or "synthetic-received"}
        end
      end
    end
  end
  table.sort(records,function(a,b) return a.tick<b.tick end)
  active.records=records
  local metadata=active.metadata
  metadata.records=#records;metadata.remote_surfaces={};metadata.created_surfaces=copy(active.created)
  for _,surface in ipairs(active.remotes) do metadata.remote_surfaces[#metadata.remote_surfaces+1]=surface.name end
  metadata.groups_per_direction=#active.remotes
  metadata.methods_per_group=2
  metadata.actual_span_seconds=span/60
  metadata.first_departure_tick=records[1].tick;metadata.last_departure_tick=records[#records].tick
end
local function aggregate(id)
  return {id=id,route_id=id,records={},shipments=0,count=0,
    sent_complete=true,received_complete=true,_sent={},_received={}}
end
local function add(target,record)
  target.records[#target.records+1]=record;target.shipments=target.shipments+1;target.count=target.shipments
  for _,kind in ipairs({"sent","received"}) do
    target[kind.."_complete"]=target[kind.."_complete"] and record[kind]~=nil
    for _,item in ipairs(record[kind] or {}) do
      local key=item.name.."/"..item.quality;local value=target["_"..kind][key]
      if not value then value={name=item.name,quality=item.quality,count=0};target["_"..kind][key]=value end
      value.count=value.count+item.count
    end
  end
end
local function finish(target)
  for _,kind in ipairs({"sent","received"}) do
    local values={};for _,item in pairs(target["_"..kind]) do values[#values+1]=item end
    table.sort(values,function(a,b) return a.name<b.name end)
    target[kind.."_observed"]=values
    target[kind]=target[kind.."_complete"] and values or nil
    target["_"..kind]=nil
  end
end
local function groups(records)
  local result={imports={},exports={}};local index={}
  for _,record in ipairs(records) do
    local group=index[record.route_id]
    if not group then
      group=aggregate(record.route_id);group.direction=record.direction
      group.remote=record.remote;group.endpoint=record.remote;group.methods={};group._methods={}
      index[record.route_id]=group;result[record.direction][#result[record.direction]+1]=group
    end
    add(group,record)
    local method=group._methods[record.method]
    if not method then
      method=aggregate(group.id..":"..record.method);method.route_id=group.id;method.method=record.method
      group._methods[record.method]=method;group.methods[#group.methods+1]=method
    end
    add(method,record)
  end
  for _,direction in ipairs({"imports","exports"}) do
    table.sort(result[direction],function(a,b) return a.remote.name<b.remote.name end)
    for _,group in ipairs(result[direction]) do
      finish(group)
      table.sort(group.methods,function(a,b) return a.method<b.method end)
      for _,method in ipairs(group.methods) do finish(method) end
      group._methods=nil
    end
  end
  return result
end

function F.install(player,surface)
  assert(not active,"Synthetic presentation fixture already installed")
  assert(player and player.valid and player.force and player.force.valid and surface and surface.valid)
  local metadata={synthetic=true,fixture_kind="synthetic-presentation-only",label="SYNTHETIC renderer data",
    source="tests/development/se_dense_presentation_fixture.lua",requested_seconds=600,
    force=player.force.name,surface=surface.name,installed_tick=game.tick,
    materials=MATERIALS,qualities={"normal"},provider_storage_modified=false,
    paired_cannon_manifests="SYNTHETIC: not supplied by the installed SE provider",
    receipt_manifests="SYNTHETIC: independently varied, never inferred from sent amounts",
    endpoint_jumps="Disabled: synthetic records do not invent physical endpoint entities",restored=false}
  active={force=player.force,surface=surface,anchor=game.tick,original=Data.query,metadata=metadata,remotes={},created={}}
  for i=1,3 do
    local remote,created=remote_surface(i);active.remotes[#active.remotes+1]=remote
    if created then active.created[#active.created+1]=remote.name end
  end
  regenerate()
  active.override=function(force,scope,tick,seconds,filters)
    if force~=active.force or scope~=active.surface or not (force.valid and scope.valid)
      or not finite(tick) or tick<0 or not finite(seconds) or seconds<0 then
      return active.original(force,scope,tick,seconds,filters)
    end
    filters=copy(filters)
    local first=math.max(0,tick-seconds*60)
    filters.from_tick,filters.to_tick=first,tick
    local selected=Data.filter(active.records,filters)
    local catalog=Data.filter(active.records,{from_tick=first,to_tick=tick,timing=filters.timing})
    local materials,qualities={},{}
    for _,record in ipairs(catalog) do
      for _,kind in ipairs({"sent","received"}) do
        for _,item in ipairs(record[kind] or {}) do materials[item.name]=true;qualities[item.quality]=true end
      end
    end
    local result={synthetic=true,fixture_kind="synthetic-presentation-only",records=selected,groups=groups(selected),
      materials={},qualities={},unpaired={},from_tick=first,to_tick=tick,seconds=(tick-first)/60,truncated=false,
      coverage={rocket=math.min(seconds,metadata.actual_span_seconds),cannon=math.min(seconds,metadata.actual_span_seconds)},
      sent_coverage=true,receipt_coverage=true}
    for material in pairs(materials) do result.materials[#result.materials+1]=material end
    for quality in pairs(qualities) do result.qualities[#result.qualities+1]=quality end
    table.sort(result.materials);table.sort(result.qualities)
    for _,record in ipairs(selected) do if record.received==nil then result.receipt_coverage=false end end
    return result
  end
  Data.query=active.override
  return metadata
end

function F.add_overflow()
  assert(active,"Install the synthetic presentation fixture first")
  if #active.remotes==3 then
    -- Seven routes per side: compact route cards fit five on a 1080p page.
    for i=4,7 do
      local remote,created=remote_surface(i);active.remotes[#active.remotes+1]=remote
      if created then active.created[#active.created+1]=remote.name end
    end
    regenerate()
  end
  return active.metadata
end

function F.restore()
  if not active then return false end
  assert(Data.query==active.override,"Another query override replaced the synthetic presentation fixture")
  Data.query=active.original;active.metadata.restored=true;active=nil
  return true
end
return F
