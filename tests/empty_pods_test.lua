script={active_mods={["space-age"]="2.1.24"}}
defines={events={on_cargo_pod_finished_ascending=1,on_cargo_pod_finished_descending=2,on_cargo_pod_delivered_cargo=3},
  inventory={cargo_unit=1,chest=2},cargo_destination={station=1,surface=2}}
storage={}
local T=require("scripts.transfers")
local force,other={valid=true,index=1},{valid=true,index=2}
local a,b={valid=true,index=1,name="A"},{valid=true,index=2,name="B"}
local silo={valid=true,type="rocket-silo",surface=a,force=force}
local hub={valid=true,type="space-platform-hub",surface=b,force=force}
local function inventory(count)
  local inv={valid=true}
  if count and count>0 then inv[1]={valid_for_read=true,name="iron-plate",count=count,quality="normal",spoil_tick=0} end
  inv.is_empty=function()return #inv==0 end;return inv
end
local id=0
local function depart(tick,count,observed)
  id=id+1
  local pod={valid=true,name="cargo-pod",unit_number=id,force=force,surface=a,
    cargo_pod_origin=silo,cargo_pod_state="ascending",cargo=inventory(count)}
  pod.get_inventory=function()return pod.cargo end
  if observed~=false then T.on_departed{cargo_pod=pod,tick=tick} end;return pod
end
local function land(pod,tick)
  pod.surface=b;pod.cargo_pod_state="descending"
  pod.cargo_pod_destination={type=defines.cargo_destination.station,station=hub}
  T.on_landed{cargo_pod=pod,tick=tick}
end
local function deliver(pod,tick,remaining,container_count)
  pod.cargo=inventory(remaining);pod.cargo_pod_state="parking"
  local container=container_count and {valid=true,surface=b,force=pod.force,
    get_inventory=function()return inventory(container_count) end}
  T.on_delivered{cargo_pod=pod,tick=tick,spawned_container=container}
end
local function query(tick)return T.boundaries(force,b,tick,1000)end
local function reset()storage={};T.on_housekeeping(0)end
reset()
local empty=depart(10);T.on_departed{cargo_pod=empty,tick=11}
assert(storage.transfers.pending_count==1 and storage.transfers.boundary_observations.count==0)
land(empty,20);package.loaded["scripts.transfers"]=nil;T=require("scripts.transfers")
deliver(empty,30);deliver(empty,30)
assert(not query(30).received_partial and #query(30).records==0 and storage.transfers.count==0,
  "Known empty delivery/replay fabricated cargo or incomplete coverage")
empty.valid=false;T.on_housekeeping(31);assert(storage.transfers.pending_count==0)
local unknown=depart(40,nil,false);land(unknown,50);deliver(unknown,60)
assert(query(60).received_partial,"Unknown empty callback must remain uncertain")
reset()
local loaded=depart(10);loaded.cargo=inventory(7);T.on_departed{cargo_pod=loaded,tick=11}
assert(storage.transfers.pending_count==1 and storage.transfers.boundary_observations.count==1)
land(loaded,20);deliver(loaded,30)
assert(#query(30).records==2 and query(30).records[1].items["iron-plate"]==7)
reset()
loaded=depart(10);loaded.cargo=inventory(9);land(loaded,20);deliver(loaded,30)
deliver(loaded,30)
local receipt=query(30)
assert(not receipt.received_partial and #receipt.records==1 and receipt.records[1].kind=="received" and receipt.records[1].items["iron-plate"]==9,
  "Late cargo was suppressed or fabricated an unobserved dispatch")
reset();empty=depart(10);land(empty,20);deliver(empty,30,nil,5)
assert(query(30).received_partial,"Nonempty container hidden by empty witness")
reset();empty=depart(10);land(empty,20);deliver(empty,30,4)
assert(query(30).received_partial,"Remaining cargo hidden by empty witness")
reset();empty=depart(10);land(empty,20);empty.force=other;deliver(empty,30)
assert(T.boundaries(other,b,30,1000).received_partial,"Force changed but inherited empty witness")
reset();empty=depart(10);land(empty,20);deliver(empty,36011)
assert(query(36011).received_partial,"Expired empty witness hid unknown delivery")
reset();empty=depart(10);land(empty,20)
local replacement=depart(11,nil,false);replacement.unit_number=empty.unit_number
land(replacement,21);deliver(replacement,30)
assert(query(30).received_partial,"Reused pod ID inherited empty witness")
reset();for i=1,4097 do depart(i) end
assert(storage.transfers.pending_count==4096,"Empty witnesses exceeded pending bound")
T.on_housekeeping(50000);assert(storage.transfers.pending_count==0)
print("EMPTY PODS PASS: witnessed emptiness, replay/reload, later cargo, unknown/expired/force/entity guards and bounds")
