-- Small GUI counterpart for the transport plots. Reuses the Sankey atlas and
-- route geometry; world-camera colour lookup must not tint these UI graphics.
local S=require('shared.sprites')
local Palette=require('shared.palette')
local Colors=require('shared.plot_colors')
local Geometry=require('scripts.ribbon_geometry')
local G={}
local function closest(colors,color)
  local best,distance
  for key,c in pairs(colors) do
    local d=((c.r or c[1])-(color.r or color[1]))^2+((c.g or c[2])-(color.g or color[2]))^2
      +((c.b or c[3])-(color.b or color[3]))^2+((c.a or c[4] or 1)-(color.a or color[4] or 1))^2
    if not distance or d<distance or (d==distance and key<best) then best,distance=key,d end
  end
  return best
end
function G.begin(parent,width,height,name)
  local root=parent.add{type='flow',direction='vertical',ignored_by_interaction=true,name=name,index=name and 1 or nil}
  root.style.width,root.style.height,root.style.vertical_spacing=width,height,0
  local P={root=root}
  local function put(spec,x,y,w,h)
    x,y,w,h=Geometry.box(x,y,w,h)
    if w<=0 or h<=0 then return end
    local wrapper=root.add{type='flow',direction='vertical',ignored_by_interaction=true}
    wrapper.style.width,wrapper.style.height=w,h
    wrapper.style.left_margin,wrapper.style.top_margin,wrapper.style.bottom_margin=x,y,-h
    local element=wrapper.add(spec)
    element.style.width,element.style.height=w,h
    local reset=root.add{type='empty-widget',ignored_by_interaction=true}
    reset.style.width,reset.style.height,reset.style.top_margin=0,0,-y
    return element
  end
  local function sprite(name,x,y,w,h)
    local e=put({type='sprite',sprite=name,resize_to_sprite=false,ignored_by_interaction=true},x,y,w,h)
    if e then e.style.stretch_image_to_widget_size=true end
    return e
  end
  function P.rect(x,y,w,h,color)
    return sprite('ssk-plot-'..closest(Colors,color),x,y,w,h)
  end
  -- Convert a strip between two sampled edges into runs of equal GUI rectangles.
  local function span(draw,x1,x2,top1,top2,bottom1,bottom2,cover_segment)
    if x2<x1 then x1,x2,top1,top2,bottom1,bottom2=x2,x1,top2,top1,bottom2,bottom1 end
    local first,last=Geometry.round(x1),Geometry.round(x2)
    local run,top,bottom=first,nil,nil
    for x=first,last-1 do
      local a=(x-first)/(last-first)
      local b=(x+1-first)/(last-first)
      local t=Geometry.round(top1+(top2-top1)*(cover_segment and math.min(a,b) or (a+b)/2))
      local u=Geometry.round(bottom1+(bottom2-bottom1)*(cover_segment and math.max(a,b) or (a+b)/2))
      if cover_segment and top2<top1 then
        t=Geometry.round(top1+(top2-top1)*b)
        u=Geometry.round(bottom1+(bottom2-bottom1)*a)
      end
      if top~=t or bottom~=u then
        if top then draw(run,top,x-run,bottom-top) end
        run,top,bottom=x,t,u
      end
    end
    if top then draw(run,top,last-run,bottom-top) end
  end
  function P.polygon(points,color)
    local name='ssk-plot-'..closest(Colors,color)
    local function draw(x,y,w,h) sprite(name,x,y,w,h) end
    -- History passes a triangle strip with its top and bottom edges interleaved.
    for i=1,#points-3,2 do
      local a,b,c,d=points[i],points[i+1],points[i+2],points[i+3]
      span(draw,a[1],c[1],a[2],c[2],b[2],d[2])
    end
  end
  local function solid_line(x1,y1,x2,y2,color,thickness)
    local name='ssk-plot-'..closest(Colors,color)
    thickness=thickness or 1
    if Geometry.round(x1)==Geometry.round(x2) or y1==y2 then
      return sprite(name,math.min(x1,x2),math.min(y1,y2),math.max(thickness,math.abs(x2-x1)),math.max(thickness,math.abs(y2-y1)))
    end
    span(function(x,y,w,h) sprite(name,x,y,w,h) end,x1,x2,y1,y2,y1+thickness,y2+thickness,true)
  end
  function P.line(x1,y1,x2,y2,color,thickness,dashed,offset)
    if not dashed then return solid_line(x1,y1,x2,y2,color,thickness) end
    local dx,dy=x2-x1,y2-y1
    local len=math.sqrt(dx*dx+dy*dy)
    for i=-(offset or 0),len-0.001,8 do
      local first,last=math.max(i,0),math.min(i+5,len)
      if first<last then solid_line(x1+dx*first/len,y1+dy*first/len,x1+dx*last/len,y1+dy*last/len,color,thickness) end
    end
  end
  function P.text(x,y,text,color,alignment,font)
    local available=alignment=='right' and x or alignment=='center' and 2*math.min(x,width-x) or width-x
    local w=math.max(1,math.min(160,available))
    local e=put({type='label',caption=text,style='grey_label',ignored_by_interaction=true},
      alignment=='right' and x-w or alignment=='center' and x-w/2 or x,y-10,w,20)
    if e then
      e.style.horizontal_align=alignment or 'left'
      e.style.single_line=true
      e.style.font=font or 'default-small'
      e.style.font_color=color
    end
  end
  function P.curve(xa,xb,ya,yb,thickness,color)
    local colors={}
    for i,c in ipairs(Palette.colors) do colors[i]={r=c[1]/255,g=c[2]/255,b=c[3]/255} end
    for i,c in ipairs(Palette.ribbon) do colors[Palette.RIBBON+i]={r=c[1]/255,g=c[2]/255,b=c[3]/255} end
    local index=closest(colors,color)
    for _,piece in ipairs(Geometry.route({t=thickness},xa,xb,ya,yb)) do
      local name=piece.kind=='bar' and S.bar(index) or piece.kind=='elbow' and S.elbow_name(piece.corner,piece.k,index)
        or S.pick(piece.dir,piece.k,index,piece.box_h)
      sprite(name,piece.x,piece.y,piece.w,piece.h)
    end
  end
  P.rect(0,0,width,height,Colors.background)
  return P
end
return G
