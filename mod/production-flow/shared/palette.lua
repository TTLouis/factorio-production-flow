-- Ribbon / node colour palette. Shared by data stage (sprite tints) and control stage.
-- 16 colours that differ in hue AND lightness (high contrast on Factorio's dark GUI),
-- plus a neutral grey (stubs) and a dim grey (de-emphasised on hover).
-- Alpha is baked into the sprite prototypes (GUI sprites cannot be tinted at runtime).
local P = {}

P.alpha = 1 -- opaque ribbons avoid dark joins; softness comes from the palette

P.colors = {
  { 0xE6, 0x19, 0x4B }, -- 1 red
  { 0x3C, 0xB4, 0x4B }, -- 2 green
  { 0xFF, 0xE1, 0x19 }, -- 3 yellow
  { 0x4F, 0x7B, 0xFF }, -- 4 blue
  { 0xF5, 0x82, 0x31 }, -- 5 orange
  { 0xB1, 0x5C, 0xE0 }, -- 6 purple
  { 0x46, 0xF0, 0xF0 }, -- 7 cyan
  { 0xF0, 0x32, 0xE6 }, -- 8 magenta
  { 0xBC, 0xF6, 0x0C }, -- 9 lime
  { 0xFA, 0xBE, 0xBE }, -- 10 pink
  { 0x1F, 0xB5, 0xA8 }, -- 11 teal
  { 0xE6, 0xBE, 0xFF }, -- 12 lavender
  { 0xC0, 0x80, 0x40 }, -- 13 brown
  { 0xFF, 0xFA, 0xC8 }, -- 14 beige
  { 0xAA, 0xFF, 0xC3 }, -- 15 mint
  { 0xFF, 0xD8, 0xB1 }, -- 16 apricot
}
P.NCAT = #P.colors
-- Muted colours keep the graph readable without stacking translucent fragments.
for _, color in ipairs(P.colors) do
  for channel = 1, 3 do color[channel] = math.floor(color[channel] * 0.65 + 156 * 0.35 + 0.5) end
end

P.GREY = P.NCAT + 1
P.grey = { color = { 0xA0, 0xA0, 0xA0 }, alpha = 0.25 }
P.DIM = P.NCAT + 2
P.dim = { color = { 0x80, 0x80, 0x80 }, alpha = 0.16 }
-- Opaque subdued variants avoid seams where GUI sprite fragments meet.
P.count = P.DIM + P.NCAT
P.quiet = {}
for i, c in ipairs(P.colors) do
  P.quiet[i] = {math.floor(c[1]*0.52+40*0.48), math.floor(c[2]*0.52+42*0.48), math.floor(c[3]*0.52+44*0.48)}
end
function P.muted(i) return i <= P.NCAT and P.DIM + i or i end
local materials = {
  ["iron-ore"]=4, ["iron-plate"]=4, ["steel-plate"]=4, ["molten-iron"]=4,
  ["copper-ore"]=5, ["copper-plate"]=5, ["copper-cable"]=5, ["molten-copper"]=5,
  water=7, steam=12, ["sulfuric-acid"]=3, sulfur=3, ["petroleum-gas"]=6,
  ["crude-oil"]=13, ["heavy-oil"]=13, ["light-oil"]=16, lubricant=2,
  ["electronic-circuit"]=2, ["advanced-circuit"]=1, ["processing-unit"]=4,
}
function P.material(key)
  key = key:gsub("#.*$", "")
  local known = materials[key:match("^[^/]+/(.+)$")]
  if known then return known end
  local h = 0
  for i=1,#key do h=(h*33+key:byte(i))%1000003 end
  return h%P.NCAT+1
end

function P.rgb(i)
  if i == P.GREY then return P.grey.color end
  if i == P.DIM then return P.dim.color end
  if i > P.DIM then return P.quiet[i-P.DIM] end
  return P.colors[i]
end

-- premultiplied tint for colour index i
function P.tint(i, alpha)
  local c, a = P.rgb(i), alpha
  if not a then
    if i == P.GREY then a = P.grey.alpha elseif i == P.DIM then a = P.dim.alpha else a = P.alpha end
  end
  return { r = c[1] / 255 * a, g = c[2] / 255 * a, b = c[3] / 255 * a, a = a }
end

return P
