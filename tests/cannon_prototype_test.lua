local manifest_file = assert(io.open('info.json', 'r'))
local manifest = manifest_file:read('*a')
manifest_file:close()
assert(manifest:find('"? space-exploration"', 1, true),
  'Space Exploration must be listed as an optional dependency for data-stage ordering')
local saved={type='direct',action_delivery={type='instant',target_effects={{type='damage',damage={amount=1,type='physical'}}}}}
mods={['space-exploration']='0.7.64'}
settings={startup={['ssk-remove-night-vision-tint']={value=false}}}
data={raw={explosion={['se-delivery-cannon-beam']={created_effect=saved}}}}
dofile('data-final-fixes.lua')
local effects=data.raw.explosion['se-delivery-cannon-beam'].created_effect
assert(effects[1]==saved and effects[2].action_delivery.target_effects[1].effect_id=='production-flow-se-cannon-dispatch')
-- Projectile and impact markers are additive too, and missing prototypes are skipped.
local listed={{type='direct'},{type='area'}}
data={raw={explosion={['se-delivery-cannon-beam']={},['se-delivery-cannon-capsule-explosion']={created_effect=listed}},
  ['artillery-projectile']={['se-delivery-cannon-capsule-artillery-projectile']={}}}}
dofile('data-final-fixes.lua')
local projectile=data.raw['artillery-projectile']['se-delivery-cannon-capsule-artillery-projectile'].created_effect
assert(#projectile==1 and projectile[1].action_delivery.target_effects[1].effect_id=='production-flow-se-cannon-projectile')
local impact=data.raw.explosion['se-delivery-cannon-capsule-explosion'].created_effect
assert(#impact==3 and impact[1]==listed[1] and impact[2]==listed[2]
  and impact[3].action_delivery.target_effects[1].effect_id=='production-flow-se-cannon-impact')
data={raw={explosion={}}}
dofile('data-final-fixes.lua')
mods={['space-exploration']='0.7.65'}
data={raw={explosion={['se-delivery-cannon-beam']={created_effect=saved}}}}
dofile('data-final-fixes.lua')
assert(data.raw.explosion['se-delivery-cannon-beam'].created_effect==saved,'Uninspected version modified')
mods={};data={raw={}}
dofile('data-final-fixes.lua')
print('CANNON PROTOTYPE PASS: additive beam/projectile/impact markers preserve prior effects, inspected version only, base unchanged')
local original={{0.25,'first'},{0.75,'second'}}
local variant={color_lookup=original,darkness_to_turn_on=0.7,energy_input='10kW'}
local base={color_lookup=original}
data.raw['night-vision-equipment']={base=base,variant=variant}
dofile('data-final-fixes.lua')
assert(base.color_lookup==original and variant.color_lookup==original,'Disabled tint setting altered an equipment LUT')
settings.startup['ssk-remove-night-vision-tint'].value=true
dofile('data-final-fixes.lua')
for _,equipment in pairs(data.raw['night-vision-equipment']) do
  assert(#equipment.color_lookup==1 and equipment.color_lookup[1][2]=='identity')
end
assert(variant.darkness_to_turn_on==0.7 and variant.energy_input=='10kW')
print('NIGHT VISION PROTOTYPES PASS: neutral lookup for each equipment, disabled mode preserves original palettes')
