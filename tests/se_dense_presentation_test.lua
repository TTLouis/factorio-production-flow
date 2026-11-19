-- Private renderer inputs must remain isolated from real provider storage.
package.loaded["scripts.sampler"]={PERIODS={600,3600}}
package.loaded["scripts.se_rockets"]={}
package.loaded["scripts.se_cannons"]={}
local Data=require("scripts.se_transfer_data")
local delegated=0
local original=function() delegated=delegated+1;return {real_provider=true} end
Data.query=original
local force={valid=true,name="player"}
local surface={valid=true,name="Nauvis",index=1}
local surfaces={Nauvis=surface}
game={tick=36000,get_surface=function(name) return surfaces[name] end,
  create_surface=function(name)
    local next_surface={valid=true,name=name,index=100}
    surfaces[name]=next_surface;return next_surface
  end}
storage={se_rockets={sentinel=true},se_cannons={sentinel=true},stock={sentinel=true}}
local rockets,cannons,stock=storage.se_rockets,storage.se_cannons,storage.stock
local Fixture=dofile("../../tests/development/se_dense_presentation_fixture.lua")
local metadata=Fixture.install({valid=true,force=force},surface)
local q=Data.query(force,surface,game.tick,600,{material="iron-plate",timing="either"})
assert(#q.records==48 and #q.groups.imports==3 and #q.groups.exports==3)
local known,unknown=0,0
for _,record in ipairs(q.records) do
  assert(record.synthetic and record.sender==nil and record.receiver==nil)
  if record.received then
    known=known+1;assert(record.sent[1].count~=record.received[1].count)
  else unknown=unknown+1;assert(record.arrival_tick==nil) end
end
assert(known==44 and unknown==4)
for _,side in ipairs({"imports","exports"}) do
  for _,group in ipairs(q.groups[side]) do assert(#group.methods==2) end
end
local cannon=Data.query(force,surface,game.tick,600,{method="cannon"})
assert(#cannon.records==24 and #cannon.materials==4)
assert(#Data.query(force,surface,game.tick,600,{quality="rare"}).records==0)
local route=q.groups.imports[1].id
local filtered=Data.query(force,surface,game.tick,600,{route=route,method="rocket",direction="imports"})
assert(#filtered.records==4)
assert(Data.query(force,{valid=true},game.tick,600,{}).real_provider and delegated==1)
local overflow=Fixture.add_overflow()
assert(overflow==metadata and overflow.records==112)
q=Data.query(force,surface,game.tick,600,{})
assert(#q.groups.imports==7 and #q.groups.exports==7)
assert(storage.se_rockets==rockets and storage.se_cannons==cannons and storage.stock==stock)
assert(Fixture.restore() and metadata.restored and Data.query==original)
assert(not Fixture.restore())
print("SE DENSE PRESENTATION PASS: method groups, independent manifests, filters, overflow, scope and restoration")
