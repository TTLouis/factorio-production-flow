-- Leave brightness activation and equipment costs to their owner. Factorio's
-- identity lookup preserves scene colours whenever this equipment is active.
if settings.startup["ssk-remove-night-vision-tint"].value then
  for _, equipment in pairs(data.raw["night-vision-equipment"] or {}) do
    equipment.color_lookup = {{1, "identity"}}
  end
end
