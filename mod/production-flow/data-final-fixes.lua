-- Leave brightness activation and equipment costs to their owner. Factorio's
-- identity lookup preserves scene colours whenever this equipment is active.
if settings.startup["ssk-chart-renderer"].value == "camera" then
  for _, equipment in pairs(data.raw["night-vision-equipment"] or {}) do
    equipment.color_lookup = {{1, "identity"}}
  end
end

-- SE 0.7.64 delivery cannon markers. Each is additive and carries no payload:
--   beam       created right after SE consumes a package (source flash)
--   projectile created on the target surface right after the beam
--   impact     created only when a landing payload spills
-- scripts/se_cannons.lua pairs them; see it for the receipt rule.
local function add_marker(prototype,effect_id)
  if not prototype then return end
  local marker={type="direct",action_delivery={type="instant",target_effects={
    {type="script",effect_id=effect_id}
  }}}
  local effects={}
  if prototype.created_effect then
    if prototype.created_effect.type then effects[1]=prototype.created_effect
    else for _,effect in ipairs(prototype.created_effect) do effects[#effects+1]=effect end end
  end
  effects[#effects+1]=marker
  prototype.created_effect=effects
end

if mods["space-exploration"]=="0.7.64" then
  local explosions=data.raw.explosion or {}
  local projectiles=data.raw["artillery-projectile"] or {}
  add_marker(explosions["se-delivery-cannon-beam"],"production-flow-se-cannon-dispatch")
  add_marker(projectiles["se-delivery-cannon-capsule-artillery-projectile"],"production-flow-se-cannon-projectile")
  add_marker(explosions["se-delivery-cannon-capsule-explosion"],"production-flow-se-cannon-impact")
end
