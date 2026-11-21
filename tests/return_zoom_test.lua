local SK, Model, View = TREQ("scripts.sankey_ui"), TREQ("scripts.model"), TREQ("scripts.view")
local player = game.players[1]
local model = { seconds=60, edges={}, residuals={}, rates={recipes={}} }
for _, name in ipairs({"water-barrel", "empty-water-barrel"}) do
  local recipe = assert(storage.graph.recipes[name])
  model.rates.recipes[name] = {normal_cps=1,cps=1}
  for _, part in ipairs(recipe.ingredients) do
    local r=model.residuals[part.key] or {prod=0,cons=0}; r.cons=r.cons+part.amount; model.residuals[part.key]=r
    model.edges[#model.edges+1]={from=part.key,to="recipe/"..name,rate=part.amount,reversing=recipe.reversing}
  end
  for _, part in ipairs(recipe.products) do
    local r=model.residuals[part.key] or {prod=0,cons=0}; r.prod=r.prod+part.amount; model.residuals[part.key]=r
    model.edges[#model.edges+1]={from="recipe/"..name,to=part.key,rate=part.amount,reversing=recipe.reversing}
  end
end
local original=Model.build
Model.build=function() return model end
player.mod_settings["ssk-return-direction-markers"]={value=true}
local c=player.gui.screen.add{type="flow",name="return_zoom_test"}
local us={view="detail",layout="clean",lines="curves",heights="sqrt",renderer="sprites",period=600,chart_fit=false,chart_zoom=1}
local function all(e,key,value,out)
  out=out or {}
  if e.tags[key]==value then out[#out+1]=e end
  for _, child in ipairs(e.children) do all(child,key,value,out) end
  return out
end
local function capture(zoom)
  us.chart_zoom=zoom
  SK.fill(player,c,us,1600,850,true)
  local markers=all(c,"ssk_return_direction","left")
  local labels=all(c,"ssk_loop_return","recipe/empty-water-barrel")
  assert(#markers>0,"fixture must have visible return direction markers")
  local coords={}
  for _,m in ipairs(markers) do
    local s=m.parent.style
    coords[#coords+1]={s.left_margin,s.top_margin,s.width,s.height}
  end
  return coords,labels
end
local one,labels=capture(1)
assert(#labels>0,"return label must be present at full detail")
local half,small_labels=capture(.5)
assert(#small_labels==0,"small zoom intentionally suppresses detailed labels")
assert(#one==#half,"zoom must preserve return marker count")
for i=1,#one do for j=1,4 do
  assert(math.abs(half[i][j]-one[i][j]*.5)<=1,"return markers must follow chart zoom")
end end
-- Exercise the same drawing and viewport pipeline for an opted-in cell graph.
local original_build, layout = View.build
View.build = function(...) layout = original_build(...); return layout end
capture(1)
View.build = function() return layout end
local cell = {chart_zoom=1}
local source = {chart_zoom=true}
local function cell_capture(zoom)
  cell.chart_zoom, cell.chart_fit = zoom, false
  SK.fill(player,c,cell,800,500,true,false,source)
  local markers=all(c,"ssk_return_direction","left")
  local coords={}
  for _,m in ipairs(markers) do
    local s=m.parent.style
    coords[#coords+1]={s.left_margin,s.top_margin,s.width,s.height}
  end
  return coords
end
local cell_one, cell_half = cell_capture(1), cell_capture(.5)
assert(#cell_one > 0 and #cell_one == #cell_half, "cell returns stay visible at both zoom levels")
for i=1,#cell_one do for j=1,4 do
  assert(math.abs(cell_half[i][j]-cell_one[i][j]*.5)<=1,"cell return markers must scale")
end end
local function click(action)
  SK.on_click({player_index=player.index,element={tags={ssk_sk=action}}},cell)
end
cell.render_zoom=2.5; click("zoom_in"); assert(cell.chart_zoom==2.5)
cell.render_zoom=.02; click("zoom_out"); assert(cell.chart_zoom==.02)
click("zoom_fit"); assert(cell.chart_fit and cell.fit_pending)
SK.fill(player,c,cell,800,500,false,false,source)
assert(cell.render_zoom <= 1 and cell.render_zoom > 0 and cell.chart_fit, "fit uses the cell viewport")
local fitted=cell.render_zoom
SK.fill(player,c,cell,800,500,false,true,source)
assert(cell.render_zoom==fitted and cell.chart_fit, "refresh preserves cell zoom")
View.build=original_build
Model.build=original
c.destroy()
print("RETURN ZOOM PASS: Full Sankey return markers scale with chart; detail labels hide below 80%")
