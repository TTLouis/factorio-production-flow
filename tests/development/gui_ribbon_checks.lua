-- Build screenshot probes from the chart's real routes and mark its GUI origin.
local Geometry = require('scripts.ribbon_geometry')
local Palette = require('shared.palette')
local Sprites = require('shared.sprites')
local T = {}

function T.equip(player)
  local armor = player.character.get_inventory(defines.inventory.character_armor)[1]
  armor.set_stack{name='modular-armor',count=1}
  local grid = assert(armor.grid)
  local battery = assert(grid.put{name='battery-equipment'})
  assert(grid.put{name='night-vision-equipment'})
  battery.energy = battery.max_energy
  player.surface.freeze_daytime = true
  player.surface.daytime = 0.5
end

local function ports(p)
  if p.kind == 'bar' then
    if p.vertical then return 'y',p.y,p.x+p.w/2,'y',p.y+p.h,p.x+p.w/2 end
    return 'x',p.x,p.y+p.h/2,'x',p.x+p.w,p.y+p.h/2
  end
  if p.kind == 'curve' then return 'x',p.x,p.ya+p.t0/2,'x',p.x+p.w,p.yb+p.t1/2 end
  local a = Geometry.arc_points(p,1)
  local x1,y1 = (a[1][1]+a[2][1])/2,(a[1][2]+a[2][2])/2
  local x2,y2 = (a[3][1]+a[4][1])/2,(a[3][2]+a[4][2])/2
  if p.corner=='bl' or p.corner=='tr' then return 'x',x1,y1,'y',y2,x2 end
  return 'x',x2,y2,'y',y1,x1
end

local function join(a,b)
  local ax, ae, ac, bx, be, bc = ports(a)
  local cx, ce, cc, dx, de, dc = ports(b)
  for _, left in ipairs{{ax,ae,ac},{bx,be,bc}} do
    for _, right in ipairs{{cx,ce,cc},{dx,de,dc}} do
      if left[1]==right[1] and math.abs(left[2]-right[2])<0.001 and math.abs(left[3]-right[3])<=1 then
        return {axis=left[1],edge=left[2],center=(left[3]+right[3])/2,
          kind=(a.kind=='elbow' or b.kind=='elbow') and 'elbow' or (a.kind=='curve' or b.kind=='curve') and 'curve' or 'straight'}
      end
    end
  end
end

local function mark_origin(canvas, result, index)
  local marker=canvas.add{type='flow',direction='horizontal',ignored_by_interaction=true,index=index}
  marker.style.width,marker.style.height,marker.style.bottom_margin=8,4,-4
  marker.style.horizontal_spacing=0
  result.marker = {}
  for _, color in ipairs{8,9} do
    local e=marker.add{type='sprite',sprite=Sprites.bar(color),resize_to_sprite=false}
    e.style.width,e.style.height,e.style.stretch_image_to_widget_size=4,4,true
    result.marker[#result.marker+1]=Palette.rgb(color)
  end
end

function T.overview_witness(paths, colors)
  local result={width=paths.style.minimal_width,height=paths.style.minimal_height,colors={},nodes={}}
  for _, color in ipairs(colors) do result.colors[#result.colors+1]=Palette.rgb(color) end
  for _, child in ipairs(paths.parent.ssk_overview_nodes.children) do
    if child.type=='flow' then
      local style=child.style
      result.nodes[#result.nodes+1]={style.left_margin,style.top_margin,style.minimal_width,style.minimal_height}
    end
  end
  mark_origin(paths,result,1)
  return result
end

function T.fit_join(canvas,player)
  local st = storage.sk_render[player.index]
  local result = {probes={}}
  for _,path in ipairs(st.paths) do
    if path.from=='item/iron-ore' and path.to=='item/iron-plate' then
      local p=Geometry.scaled_piece(path.pieces[1],st.display_zoom)
      local axis,edge,center=ports(p)
      assert(axis=='x' and p.kind=='bar','The fixture must start at the ore bar')
      result.probes[1]={axis=axis,edge=edge,center=center,kind='node'}
      break
    end
  end
  assert(#result.probes==1,'Missing the fitted ore ribbon')
  mark_origin(canvas,result)
  return result
end

function T.inspect(canvas,player,case)
  local st = storage.sk_render[player.index]
  local sprite = st.ribbons[1].elem ~= nil
  assert(sprite == (case.renderer=='sprites'),'Unexpected ribbon backend')
  local energy
  if case.night_vision then
    for _, equipment in pairs(player.character.get_inventory(defines.inventory.character_armor)[1].grid.equipment) do
      if equipment.type=='night-vision-equipment' then energy=equipment.energy end
    end
    assert(energy and energy>0,'Night vision is unpowered')
  end

  local result = {backend=sprite and 'sprites' or 'poly', night_vision_energy=energy,
    tint_override=settings.startup['ssk-chart-renderer'].value=='camera', elbows=0, probes={}}
  local last, steep = {}, 0
  for _,path in ipairs(st.paths) do
    local key = path.from .. '>' .. path.to
    for _, piece in ipairs(path.pieces) do
      if piece.kind=='elbow' then
        result.elbows = result.elbows+1
        if key=='item/copper-plate>item/automation-science-pack' then steep=steep+1 end
      end
      if last[key] then
        local probe = join(last[key],piece)
        if probe then result.probes[#result.probes+1]=probe end
      end
      last[key]=piece
    end
  end
  assert(steep>=2,'Steep copper plate flow did not keep a rounded bend in curves mode')

  mark_origin(canvas,result)
  return result
end

return T
