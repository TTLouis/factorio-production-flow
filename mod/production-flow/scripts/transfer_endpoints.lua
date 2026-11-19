-- Known physical endpoints, independent of shipment quantities/outcomes.
local E={}

function E.snapshot(entity,kind)
  if not (entity and entity.valid and entity.unit_number and entity.surface and entity.surface.valid
    and entity.force and entity.force.valid and entity.position) then return nil end
  return {entity=entity,unit_number=entity.unit_number,name=entity.name,surface=entity.surface,
    force=entity.force,position={x=entity.position.x,y=entity.position.y},kind=kind}
end

return E
