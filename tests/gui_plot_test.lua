local G=TREQ('scripts.gui_plot')
local SK=TREQ('scripts.sankey_ui')
local player=game.players[1]
local original=player.get_inventory
player.get_inventory=function(inventory)
  assert(inventory~=defines.inventory.character_armor,'Renderer choice should not inspect armor')
  return original and original(inventory)
end
local root=player.gui.screen.add{type='flow',name='gui_plot_test',direction='vertical'}
local p=G.begin(root,400,200)
p.rect(10,20,30,40,{r=.92,g=.58,b=.30,a=1})
p.line(5,5,390,5,{r=.34,g=.34,b=.35,a=1},1)
p.curve(30,300,40,90,12,{r=.28,g=.59,b=.64,a=1})
p.text(50,10,'test',{r=.76,g=.76,b=.76,a=1},'left')
for _,scale in ipairs({1,1.25,1.5}) do
  local function px(v)local n=(v or 0)*scale;return n<0 and math.ceil(n) or math.floor(n) end
  local cursor=0
  for _,e in ipairs(p.root.children) do cursor=cursor+px(e.style.top_margin)+px(e.style.height)+px(e.style.bottom_margin) end
  assert(cursor==0,'GUI plot primitives moved the next hover target at fractional scale')
end
for _,renderer in ipairs{'sprites','poly'} do
  root.clear()
  SK.fill(player,root,{view='focus',focus='item/electronic-circuit',focus_steps=2,renderer=renderer,period=600},1000,700,true)
  local ribbons=storage.sk_render['1:focus'].ribbons
  assert(#ribbons>0)
  for _,r in ipairs(ribbons) do assert((r.ro~=nil)==(renderer=='poly'),'Chart did not use the selected renderer') end
end
root.destroy();player.get_inventory=original
print('GUI PLOT PASS: selected renderer, shared ribbon geometry and exact fractional-scale positioning')
