-- Known physical endpoints, independent of shipment quantities/outcomes.
local E={}

function E.snapshot(entity,kind,zone)
  if not (entity and entity.valid and entity.unit_number and entity.surface and entity.surface.valid
    and entity.force and entity.force.valid and entity.position) then return nil end
  return {entity=entity,unit_number=entity.unit_number,name=entity.name,surface=entity.surface,
    force=entity.force,position={x=entity.position.x,y=entity.position.y},kind=kind,zone=zone}
end

function E.resolve(endpoint,force)
  local entity=endpoint and endpoint.entity
  if not (force and force.valid and endpoint and endpoint.force==force and entity and entity.valid
    and endpoint.surface and endpoint.surface.valid and entity.surface==endpoint.surface
    and entity.force==force and entity.unit_number==endpoint.unit_number and entity.name==endpoint.name) then return nil end
  return entity
end

function E.can_jump(player,endpoint)
  local api=remote and remote.interfaces and remote.interfaces["space-exploration"]
  return player and player.valid and E.resolve(endpoint,player.force)~=nil
    and player.controller_type~=defines.controllers.cutscene
    and api and api.get_zone_from_surface_index and api.remote_view_start and api.remote_view_is_active and true or false
end

-- SE's public remote-view API keeps control of unlock rules. Never teleport a
-- character, discover a zone, or close the caller's GUI on a rejected jump.
function E.jump(player,endpoint,close)
  if not E.can_jump(player,endpoint) then return false,"unavailable" end
  local entity=E.resolve(endpoint,player.force)
  local ok,zone=pcall(remote.call,"space-exploration","get_zone_from_surface_index",{surface_index=entity.surface.index})
  if not (ok and zone and zone.name and zone.surface_index==entity.surface.index) then return false,"unknown-surface" end
  local position={x=entity.position.x,y=entity.position.y}
  local started,failure=pcall(remote.call,"space-exploration","remote_view_start",{player=player,zone_name=zone.name,position=position})
  if not started then return false,failure end
  local checked,active=pcall(remote.call,"space-exploration","remote_view_is_active",{player=player})
  if not (checked and active and player.surface==entity.surface) then return false,"view-not-opened" end
  if close then close(player) end
  return true
end

return E
