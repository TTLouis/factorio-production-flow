-- Test-only canvas hit model. Checks native geometry and event opt-ins before
-- any handler is invoked; it does not synthesize engine mouse events.
local T = {}
local function length(style, name)
  -- LuaStyle width/height are write-only. Native minimums are readable and
  -- reflect an explicit size; only the offline table mock needs the fallback.
  local minimum = name == "width" and "minimal_width" or name == "height" and "minimal_height"
  if minimum then
    local value = style[minimum]
    if type(value) == "number" then return value end
  end
  local value = style[name]
  return type(value) == "number" and value or 0
end
local function inside(b,x,y) return x>=b.x and y>=b.y and x<b.x+b.w and y<b.y+b.h end
local function snapshot(canvas,scale)
  local out,y={},0
  local function px(v) local n=v*scale;return n<0 and math.ceil(n) or math.floor(n) end
  local function element(e,x,y,is_child)
    local style=e.style
    local top,height=length(style,"top_margin"),length(style,"height")
    local n={type=e.type,tags=e.tags,visible=e.visible~=false,ignored=e.ignored_by_interaction,
      top_margin=top,height=height,
      box={x=x+px(length(style,"left_margin")),y=y+px(top),w=px(length(style,"width")),h=px(height)}}
    if is_child then n.tooltip,n.raise_hover_events=e.tooltip,e.raise_hover_events
    else n.bottom_margin=length(style,"bottom_margin") end
    return n
  end
  -- Each children access clones a native GUI array. Read each array once,
  -- together with the element facts used by every subsequent hit comparison.
  local canvas_children=canvas.children
  for i,e in ipairs(canvas_children) do
    local wrapper=element(e,0,y,false)
    local children=e.children
    wrapper.children={}
    for j,child in ipairs(children) do
      wrapper.children[j]=element(child,wrapper.box.x,wrapper.box.y,true)
    end
    out[i]=wrapper
    y=y+px(wrapper.top_margin)+wrapper.box.h+px(wrapper.bottom_margin)
  end
  return out
end
local function hit(wrappers,x,y)
  for i=#wrappers,1,-1 do
    local wrapper=wrappers[i]
    -- Factorio's ignored flag also excludes descendants from hit testing.
    if wrapper.visible and not wrapper.ignored then
      for j=#wrapper.children,1,-1 do
        local child=wrapper.children[j]
        if child.visible and not child.ignored and inside(child.box,x,y) then return child end
      end
      if inside(wrapper.box,x,y) then return wrapper end
    end
  end
end
function T.inspect(canvas,scale)
  local out={icons=0,bars=0,ribbons=0,hover_enabled=0,stub_targets=0,obstructions={},wrappers=0,oversized_wrappers=0,rows={},labels=0,label_alignment_errors={}}
  local columns={}
  local icons,labels={},{}
  local wrappers=snapshot(canvas,scale)
  for _,wrapper in ipairs(wrappers) do
    if wrapper.type=="flow" then
      out.wrappers=out.wrappers+1
      local child=wrapper.children[1]
      if child and (child.top_margin~=0 or wrapper.height~=child.height) then
        out.oversized_wrappers=out.oversized_wrappers+1
      end
    end
    for _,e in ipairs(wrapper.children) do
      if e.tags.ssk_label and e.visible then
        labels[e.tags.ssk_label]=e.box
      end
      local tip=e.tooltip
      if e.type=="sprite" and type(tip)=="table" and (tip[1]=="production-flow.sankey-other-sources-of-s-outside-this-view"
        or tip[1]=="production-flow.sankey-other-uses-of-s-not-shown-outside"
        or tip[1]=="production-flow.sankey-estimated-from-consumption-outside-recorded-recipes") then
        out.stub_targets=out.stub_targets+1
      end
      if e.tags.ssk_sk=="ribbon" then
        out.ribbons=out.ribbons+1
        if e.raise_hover_events then out.hover_enabled=out.hover_enabled+1 end
      elseif e.tags.ssk_sk=="node" and e.visible then
        local b=e.box
        local kind=e.type=="sprite-button" and "icon" or "bar"
        out[kind=="icon" and "icons" or "bars"]=out[kind=="icon" and "icons" or "bars"]+1
        local x,y=b.x+b.w/2,b.y+b.h/2
        local found=hit(wrappers,x,y)
        if found~=e then out.obstructions[#out.obstructions+1]={key=e.tags.key,kind=kind,x=x,y=y,
          received_type=found and found.type or "none",received_key=found and found.tags.key} end
        if kind=="icon" then
          icons[e.tags.key]=b
          local col=columns[b.x] or {};columns[b.x]=col
          col[#col+1]={key=e.tags.key,x=x,y=y,reachable=found==e}
        end
      end
    end
  end
  for key,label in pairs(labels) do
    local icon=icons[key]
    if icon then
      out.labels=out.labels+1
      if label.x~=icon.x or label.y+label.h>icon.y then
        out.label_alignment_errors[#out.label_alignment_errors+1]={key=key,label=label,icon=icon}
      end
    end
  end
  -- Report top/middle/bottom in each column, independent of pairs iteration order.
  local xs={};for x in pairs(columns) do xs[#xs+1]=x end;table.sort(xs)
  for _,x in ipairs(xs) do
    local col=columns[x];table.sort(col,function(a,b)return a.y<b.y end)
    if #col>=3 then out.rows[#out.rows+1]={top=col[1],middle=col[math.ceil(#col/2)],bottom=col[#col]} end
  end
  return out
end
function T.assert_clear(result, expect_ribbons)
  assert(result.icons>0 and result.bars>0,"Empty chart interaction fixture")
  assert(result.oversized_wrappers==0,"Absolute-position wrapper can intercept earlier chart rows")
  assert(#result.obstructions==0,"Chart node is covered by another interactive element")
  assert((expect_ribbons==false or result.ribbons>0) and result.ribbons==result.hover_enabled,
    "Ribbon hover/leave events are not enabled")
  assert(#result.label_alignment_errors==0,"Material label is displaced from or overlaps its item icon")
end

function T.assert_show_hidden_position(panel)
  local rows=panel.ssk_bar.ssk_toolbar_strip.ssk_toolbar_rows
  assert(#rows.children==1,"Show hidden added a toolbar row")
  local controls=rows.ssk_toolbar_main.ssk_toolbar_actions.children
  for index, control in ipairs(controls) do
    if control.tags.ssk_sk=="unhide_all" then
      assert(controls[index+1] and controls[index+1].tags.ssk_sk=="zoom_out",
        "Show hidden must be immediately left of zoom out")
      return control
    end
  end
  error("Show hidden is missing from the zoom controls")
end
return T
