-- Isolated presentation contract; providers are stubs, never private SE state.
local a={valid=true,index=1,name="Nauvis"}
local b={valid=true,index=2,name="Orbit"}
local own={valid=true,index=1}
local foreign={valid=true,index=2}
local raw_rockets,raw_cannons={},{}
local rocket_truncated,cannon_truncated=false,false
package.loaded["scripts.sampler"]={PERIODS={60,3600}}
package.loaded["scripts.se_rockets"]={query=function(force,surface,tick,seconds)
  assert(seconds==3600,"History must fetch retained records before choosing boundary time")
  return {records=raw_rockets,seconds=500,truncated=rocket_truncated}
end}
package.loaded["scripts.se_cannons"]={query=function(force,surface,tick,seconds)
  assert(seconds==3600)
  return {observations=raw_cannons,seconds=30,truncated=cannon_truncated}
end}
local D=require("scripts.se_transfer_data")
local function stack(name,count,quality) return {name=name,count=count,quality=quality or "normal"} end
local function endpoint(sf) return {surface=sf,zone=sf.index,name=sf.name} end
local function rocket(id,tick,from,to,sent,received,arrival,force)
  return {id=id,force=force or own,departure_tick=tick,from=endpoint(from),to=endpoint(to),
    sender={surface=from,force=force or own,unit_number=id,position={x=id,y=0}},
    receiver={surface=to,force=force or own,unit_number=id+100,position={x=0,y=0}},
    sent=sent,received=received,arrival_tick=arrival,status="unconfirmed"}
end
raw_rockets={
  rocket(1,6500,a,b,{stack("iron",1000),stack("iron",2,"rare")},{stack("iron",992)},9000),
  rocket(2,6000,b,a,{stack("iron",200)},{stack("iron",190)},7000),
  rocket(3,8000,b,a,{stack("copper",100)},nil,8200), -- arrival without a receipt manifest is not a quantity observation.
  rocket(4,8100,a,a,{stack("iron",20)}),
  rocket(5,8200,a,b,{stack("iron",30)},nil,nil,foreign),
}
raw_cannons={
  {id=1,tick=8500,sender={surface=a,force=own,unit_number=50,position={x=5,y=6}},shot_count=1},
  {id=2,tick=8600,sender={surface=b,force=own,unit_number=51}},
  {id=3,tick=8700,sender={surface=a,force=foreign,unit_number=52}},
}
local q=D.query(own,a,10000,60)
assert(q.from_tick==6400 and q.to_tick==10000 and q.seconds==60)
assert(q.coverage.rocket==60 and q.coverage.cannon==30)
assert(#q.records==3 and #q.unpaired==1)
assert(#q.groups.imports==1 and #q.groups.exports==1)
local imports,exports=q.groups.imports[1],q.groups.exports[1]
assert(imports.id=="imports:2" and exports.id=="exports:2")
assert(exports.endpoint.surface==b and exports.remote.surface==b)
assert(exports.count==1 and exports.shipments==1 and #exports.methods==1 and exports.methods[1].method=="rocket")
assert(exports.methods[1].sent[1].name=="iron" and exports.methods[1].sent[1].count==1000)
assert(exports.methods[1].sent[2].quality=="rare" and exports.methods[1].sent[2].count==2)
assert(imports.received==nil and imports.received_complete==false and #imports.received_observed==0)
local c=q.unpaired[1]
assert(c.key=="cannon:1" and c.direction=="unpaired" and c.method=="cannon" and c.unknown_payload)
assert(c.remote==nil and c.route_id==nil and c.to==nil and c.sent==nil and c.received==nil)
assert(c.sender.unit_number==50 and c.sender.position.x==5)
assert(#q.materials==2 and q.materials[1]=="copper" and q.materials[2]=="iron")
assert(#q.qualities==2 and q.qualities[1]=="normal" and q.qualities[2]=="rare")
-- All copied manifest/endpoint tables may be decorated by UI without changing provider evidence.
exports.records[1].sent[1].count=1
exports.records[1].sender.position.x=99
assert(raw_rockets[1].sent[1].count==1000 and raw_rockets[1].sender.position.x==1)
local filtered=D.query(own,a,10000,60,{material="iron",quality="rare"})
assert(#filtered.records==1 and #filtered.unpaired==0)
assert(#filtered.records[1].sent==1 and filtered.records[1].sent[1].count==2)
assert(filtered.records[1].received~=nil and #filtered.records[1].received==0,"Known absent selected quality must remain distinct from unknown receipt")
assert(#filtered.materials==2,"Active filters changed material choices")
assert(#D.query(own,a,10000,60,{method="cannon"}).records==1)
assert(#D.query(own,a,10000,60,{method="cannon",material="iron"}).records==0,"Unknown cannon payload attributed to a material")
assert(#D.query(own,a,10000,60,{direction="exports"}).records==1,"Unpaired cannon invented an export")
assert(#D.query(own,a,10000,60,{route="imports:2"}).records==1)
-- Receipt-window queries include older departures and never create unknown arrival quantities.
local history=D.query(own,a,10000,60,{timing="either"})
assert(#history.records==4 and #history.groups.imports[1].records==2)
local combined=history.groups.imports[1]
assert(combined.received==nil and not combined.received_complete)
assert(#combined.received_observed==1 and combined.received_observed[1].count==190,"Partial observed receipt evidence lost")
assert(combined.sent[1].name=="copper" and combined.sent[2].name=="iron")
local receipts=D.query(own,a,10000,60,{timing="arrival",direction="imports"})
assert(#receipts.records==1 and receipts.records[1].key=="rocket:2")
assert(receipts.groups.imports[1].received[1].count==190)
assert(#D.query(own,a,10000,60,{timing="arrival",bucket=8000,bucket_ticks=1000}).records==0,"Unknown receipt or closed bucket edge was plotted")
local bucket=D.query(own,a,10000,60,{bucket=8000,bucket_ticks=1000})
assert(#bucket.records==2 and bucket.records[1].key=="cannon:1" and bucket.records[2].key=="rocket:3")
assert(#D.query(own,a,10000,60,{bucket=8000,bucket_ticks=0}).records==0)
-- Existing surface indexes do not authorize a different surface generation or force.
assert(#D.query(own,{valid=true,index=1,name="Replacement"},10000,60).records==0)
assert(#D.query(foreign,a,10000,60).records==2)
assert(#D.query({valid=false},a,10000,60).records==0)
assert(#D.query(own,{valid=false},10000,60).records==0)
assert(#D.query(own,a,0/0,60).records==0)
assert(#D.query(own,a,10000,-1).records==0)
rocket_truncated=true;cannon_truncated=false
assert(D.query(own,a,10000,60).truncated)
assert(not D.query(own,a,10000,60,{method="cannon"}).truncated)
rocket_truncated=false;cannon_truncated=true
assert(not D.query(own,a,10000,60,{method="rocket"}).truncated)
assert(D.query(own,a,10000,60,{method="cannon"}).truncated)
print("SE TRANSFER DATA PASS: grouped methods, exact sent/received qualities, independent timing/buckets, unpaired cannon evidence, isolation and copy safety")
