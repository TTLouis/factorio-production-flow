local E=require("scripts.transfer_endpoints")
defines={controllers={cutscene=6}}
local force={valid=true,index=1}
local surface={valid=true,index=1}
local other={valid=true,index=2}
local entity={valid=true,name="se-delivery-cannon",unit_number=40,surface=surface,force=force,position={x=3,y=7}}
local endpoint=assert(E.snapshot(entity,"cannon_sender"))
assert(endpoint.position.x==3 and E.resolve(endpoint,force)==entity and not E.resolve(endpoint,other))
entity.position.x=9
assert(endpoint.position.x==3,"Snapshot position changed with the entity")
local player={valid=true,force=force,surface=surface}
local closed=false
remote={interfaces={['space-exploration']={get_zone_from_surface_index=true,remote_view_start=true,remote_view_is_active=true}},
  call=function(_,method,data)
    if method=='get_zone_from_surface_index' then return {name='Nauvis',surface_index=1} end
    if method=='remote_view_start' then assert(data.player==player and data.position.x==9);return end
    if method=='remote_view_is_active' then return true end
  end}
assert(E.jump(player,endpoint,function() closed=true end) and closed)
player.controller_type=defines.controllers.cutscene
assert(not E.can_jump(player,endpoint),"Cutscene jump must leave the player controller alone")
player.controller_type=nil
closed=false
entity.force=other
assert(not E.jump(player,endpoint,function() closed=true end) and not closed)
entity.force=force;entity.valid=false
assert(not E.resolve(endpoint,force) and not E.can_jump(player,endpoint))
entity.valid=true;entity.surface=other
assert(not E.resolve(endpoint,force),"Moved surface silently retargeted historical endpoint")
entity.surface=surface
remote.call=function(_,method)
  if method=='get_zone_from_surface_index' then return {name='Nauvis',surface_index=1} end
  if method=='remote_view_is_active' then return false end
end
assert(not E.jump(player,endpoint,function() closed=true end) and not closed,"Rejected view closed GUI")
remote.interfaces={}
assert(not E.can_jump(player,endpoint))
print('TRANSFER ENDPOINTS PASS: immutable snapshots, stale/foreign/moved targets, public remote view and rejected jumps')
