-- Private-stage fixture for native closed/open transport-query comparisons.
-- Call seed with two real surfaces and game.tick >= 10000. Never load this
-- module into the user's live profile or package it into a candidate archive.
local Fixture={}
local T=require("scripts.transfers")
local retention=require("scripts.sampler").PERIODS
local LIMIT=32768
local names={"iron-plate","copper-plate","steel-plate","stone","coal","iron-ore"}
local moving={}

function Fixture.seed(force, surface, remote, tick)
  assert(force.valid and surface.valid and remote.valid and surface~=remote)
  assert(tick>=10000,"Warm the isolated map before seeding this fixture")
  local from={id=1,surface=surface,name=surface.name}
  local to={id=2,surface=remote,name=remote.name}
  local observations={history={},first=1,count=LIMIT,serial=LIMIT,seen={},dropped={},
    start_tick=0,sent_by_pod={}}
  local state={pending={},pending_count=0,endpoints={[surface.index]=from,[remote.index]=to},
    serial=2,history={},first=1,count=LIMIT/2,dropped={},recording_start=0,
    boundary_observations=observations}
  local list={}
  moving={}
  for id=1,LIMIT/2 do
    -- Most traffic lies far outside a five-second query. The final four
    -- receipts are recent; one of their dispatches is 9000 ticks older.
    local recent=id>LIMIT/2-4
    local departure=tick-10000+math.floor(id/4)
    local arrival=departure+1
    if recent then
      departure=tick-(id==LIMIT/2 and 9000 or 50)
      arrival=tick-(LIMIT/2-id)*5
    end
    local items,received,sent_contents,received_contents={},{},{},{}
    for j,name in ipairs(names) do
      local count=10+j+id%7
      items[name]=count;received[name]=count-1
      sent_contents[j]={name=name,count=count,quality=j%2==0 and "rare" or "normal"}
      received_contents[j]={name=name,count=count-1,quality=sent_contents[j].quality}
    end
    local origin,destination=from,to
    if id%2==0 then origin,destination=to,from end
    local shipment="fixture:"..id
    local sent={id=id*2-1,key=shipment..":sent",shipment_id=shipment,pod_id=id,
      kind="sent",tick=departure,force=force,from=origin,to=destination,
      destination_tick=arrival-1,items=items,contents=sent_contents,quality_exact=true}
    local receipt={id=id*2,key=shipment..":received",shipment_id=shipment,
      kind="received",tick=arrival,force=force,from=origin,to=destination,
      items=received,contents=received_contents,quality_exact=true}
    list[#list+1]=sent;list[#list+1]=receipt
    observations.seen[sent.key]=true;observations.seen[receipt.key]=true
    observations.sent_by_pod[id]=sent
    state.history[id]={tick=arrival,force=force,from=origin,to=destination,
      items=received,shipment_id=shipment}
    if recent then moving[#moving+1]={sent=sent,receipt=receipt,arrival=state.history[id],
      departure_offset=tick-departure,arrival_offset=tick-arrival,long=id==LIMIT/2} end
  end
  local function order(a,b) if a.tick~=b.tick then return a.tick<b.tick end;return a.key<b.key end
  table.sort(list,order)
  observations.history=list
  table.sort(state.history,function(a,b)return a.tick<b.tick end)
  storage.transfers=state
  local selected=T.boundaries(force,surface,tick,5,{companions=true})
  assert(#selected.records==8,"Fixture selected-boundary total changed")
  assert(#T.boundaries(force,surface,tick,10000).records==LIMIT,"Fixture ledger is not full")
  return {boundaries=LIMIT,shipments=LIMIT/2,selected_boundaries=8,manifest_stacks=#names}
end

-- Reconstruct only the private refresh references after loading the exact
-- seeded save. Canonical ledger contents themselves are not regenerated.
function Fixture.attach()
  local state=assert(storage.transfers)
  local observations=assert(state.boundary_observations)
  assert(observations.count==LIMIT and state.count==LIMIT/2)
  local pairs_by_id={}
  for id=LIMIT/2-3,LIMIT/2 do pairs_by_id["fixture:"..id]={long=id==LIMIT/2} end
  local latest=0
  for i=0,observations.count-1 do
    local record=observations.history[(observations.first-1+i)%LIMIT+1]
    local pair=pairs_by_id[record.shipment_id]
    if pair then
      pair[record.kind=="sent" and "sent" or "receipt"]=record
      if record.kind=="received" then latest=math.max(latest,record.tick) end
    end
  end
  for i=0,state.count-1 do
    local arrival=state.history[(state.first-1+i)%LIMIT+1]
    local pair=pairs_by_id[arrival.shipment_id]
    if pair then pair.arrival=arrival end
  end
  moving={}
  for id=LIMIT/2-3,LIMIT/2 do
    local pair=pairs_by_id["fixture:"..id]
    assert(pair.sent and pair.receipt and pair.arrival,"Incomplete saved fixture")
    pair.departure_offset=latest-pair.sent.tick
    pair.arrival_offset=latest-pair.receipt.tick
    moving[#moving+1]=pair
  end
end

-- Run before the product's 300-tick UI refresh. Keep four synthetic recent
-- shipments active throughout a long benchmark; old traffic remains fixed.
-- This changes only eight boundary records and four receipt references.
function Fixture.refresh(tick)
  for _,pair in ipairs(moving) do
    if not pair.long then pair.sent.tick=tick-pair.departure_offset end
    pair.receipt.tick=tick-pair.arrival_offset
    pair.sent.destination_tick=pair.receipt.tick-1
    pair.arrival.tick=pair.receipt.tick
  end
end

-- Baseline reproduces the former full-retention retrieval before the selected
-- window filter. Apply only in the isolated baseline mod copy.
function Fixture.full_retention_baseline()
  local original=T.boundaries
  T.boundaries=function(force,surface,tick)
    return original(force,surface,tick,retention[#retention])
  end
end

return Fixture
