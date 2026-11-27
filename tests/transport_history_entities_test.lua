local N=TREQ("scripts.transport_history_entities")
local Panels=TREQ("scripts.se_transfer_panels")
local player=game.players[1]
local us=storage.ui[player.index]
local force,surface=player.force,player.surface
local saved=us.transport_entity_favs;us.transport_entity_favs={}
local function endpoint(id,name,kind,sf,owner)
  return {unit_number=id,name=name,kind=kind,surface=sf or surface,force=owner or force,entity={valid=false}}
end
local a=endpoint(2001,"se-rocket-launch-pad","rocket_sender")
local b=endpoint(2002,"se-rocket-launch-pad","rocket_sender")
local c=endpoint(2003,"se-delivery-cannon","delivery-cannon")
local d=endpoint(2004,"se-delivery-cannon","delivery-cannon")
local foreign=endpoint(2005,"se-rocket-launch-pad","rocket_sender",surface,{valid=true})
local away=endpoint(2006,"se-rocket-launch-pad","rocket_sender",{index=991,valid=true})
local items={{name="iron-plate",count=100,quality="normal"}}
local data={from_tick=game.tick-600,to_tick=game.tick,records={
  {key="entity:a",method="rocket",direction="exports",tick=game.tick-180,sender=a,sent=items},
  {key="entity:a2",method="rocket",direction="exports",tick=game.tick-120,sender=a,receiver=a,sent=items},
  {key="entity:b",method="rocket",direction="exports",tick=game.tick-60,sender=b,receiver=away,sent=items},
  {key="entity:c",method="cannon",direction="unpaired",tick=game.tick-30,sender=c}}}
local entries,map=N.entries(data,surface,force,{cannons={{endpoint=d},{endpoint=foreign}}})
assert(#entries==4 and map[N.key(a,surface,force)].count==2,"Duplicate endpoints double counted one record")
assert(N.key(foreign,surface,force)==nil and N.key(away,surface,force)==nil,"Foreign or remote entities leaked into the list")
assert(entries[1].group=="cannon" and entries[3].group=="rocket_sender","Entity groups have unstable ordering")
local fixture=player.gui.screen.add{type="flow",name="entity_history_test",direction="vertical"}
local state={history={}}
local function render() N.render(fixture,player,surface,10,state,1200,650,data,{cannons={{endpoint=d}}}) end
local function find(e,predicate)
  if predicate(e) then return e end
  for _,child in ipairs(e.children) do local hit=find(child,predicate);if hit then return hit end end
end
render();local root=fixture.entity_history
assert(not root.divider and root.sidebar.spec.type=="frame" and root.main.spec.type=="frame"
  and root.sidebar.spec.style=="inside_deep_frame" and root.main.spec.style==root.sidebar.spec.style
  and root.sidebar.style.padding==0 and root.main.style.padding==4
  and root.sidebar.style.height==650 and root.main.style.height==650
  and root.sidebar.style.width+root.main.style.width+root.style.horizontal_spacing==1200,
  "History must reuse Balance's sibling inset panels with matching depth, padding and exact width")
assert(state.history.entity==nil and root.sidebar.box.total.children[1].toggled and #Panels.last_records(state.history)==4,"Total must be the default aggregate")
local key=N.key(a,surface,force)
local pick=assert(find(root,function(e)return e.tags.history_entity==key end))
assert(N.on_click({element=pick,player_index=player.index},state));render()
assert(state.history.entity==key and #Panels.last_records(state.history)==2,"Entity selection did not filter timeline/log input")
assert(#data.records==4 and data.records[1].sent[1].count==100,"Entity filtering mutated source records")
local search=root.sidebar.strip.controls.search;search.text="2002"
assert(N.on_text_changed({element=search},state));render()
assert(fixture.entity_history==root and root.sidebar.strip.controls.search==search,"Search refresh rebuilt focused controls")
assert(find(root.sidebar.box.scroll,function(e)return e.tags.history_entity==N.key(b,surface,force) end)
  and not find(root.sidebar.box.scroll,function(e)return e.tags.history_entity==key end),"Entity search did not narrow the list")
assert(N.on_click({element={valid=true,tags={history_entity_clear_search=true}},player_index=player.index},state));render()
local star=assert(find(root,function(e)return e.tags.history_entity_favourite==key end))
assert(star.spec.style=="tool_button" and star.style.width==24)
assert(N.on_click({element=star,player_index=player.index},state) and us.transport_entity_favs[key]);render()
state.history.bucket=game.tick-600;state.history.exchange="old"
assert(N.on_click({element=root.sidebar.box.total.children[1],player_index=player.index},state));render()
assert(state.history.entity==nil and state.history.bucket==nil and state.history.exchange==nil and #Panels.last_records(state.history)==4)
assert(N.on_click({element={valid=true,tags={history_entity=key}},player_index=player.index},state));render()
assert(state.history.entity==key,"Destroyed historical entities lost their recorded identities")
data.records={};render()
assert(state.history.entity==nil and #Panels.last_records(state.history)==0,"Expired selection did not return to Total")
assert(N.on_click({element={valid=true,tags={history_entity="untrusted"}},player_index=player.index},state))
assert(state.history.entity==nil,"Forged entity key selected unrelated history")
fixture.destroy();us.transport_entity_favs=saved
print("HISTORY ENTITIES PASS: Total default, scoped groups, unique record counts, focus, favourites, search stability, immutable data and safe expiry")
