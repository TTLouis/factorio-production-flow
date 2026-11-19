-- Saved-map cameras must chart their full generated region without widening
-- the rendering objects' per-player visibility.
package.path="./?.lua;"..package.path
storage={}
local area,requests,generated=nil,0,0
local function make_surface(index)
  local s={index=index,valid=true,chunks={},map_gen_settings={width=0,height=0}}
  s.request_to_generate_chunks=function(pos)
    assert(s.generate_with_lab_tiles,"Canvas requested a normal map chunk")
    requests=requests+1
    s.chunks[math.floor(pos[1]/32)..","..math.floor(pos[2]/32)]=true
  end
  s.is_chunk_generated=function(pos)return s.chunks[pos[1]..","..pos[2]] or false end
  s.force_generate_chunk_requests=function()generated=generated+1 end
  s.set_tiles=function() error("Canvas must not repaint native lab chunks") end
  return s
end
local surface=make_surface(14)
surface.map_gen_settings={width=64,height=64,seed=137}
game={get_surface=function()return surface end,forces={}}
local force={chart=function(s,a)assert(s==surface);area=a end}
local serial=0
rendering={draw_rectangle=function(spec)
  serial=serial+1
  local o={valid=true,players=spec.players,id=serial}
  o.destroy=function()o.valid=false end
  return o
end}
local C=require("scripts.canvas")
local a={index=1,force=force}
C.begin(a,916,668)
assert(surface.map_gen_settings.width==0 and surface.map_gen_settings.height==0 and surface.map_gen_settings.seed==137,
  "legacy finite canvas dimensions must expand without replacing its other settings")
assert(surface.generate_with_lab_tiles and surface.always_day and surface.freeze_daytime and surface.daytime==0,
  "Existing canvas must switch to daylight lab generation")
assert(requests>0 and generated==1)
assert(area[1][1]==480 and area[1][2]==-32 and area[2][1]==576 and area[2][2]==32,
  "camera edge chunks must be fully charted, not only its fractional plot bounds")
local old=storage.canvas[1].objs[1]
assert(old.players[1]==1 and #old.players==1)
local before=requests
area=nil
C.begin(a,916,668)
assert(requests==before and area,"cached chunks still need charting for the current force")
surface.map_gen_settings.width,surface.map_gen_settings.height=2000000,2000000
C.begin(a,916,668)
assert(requests==before and generated==1,
  "native normalized unlimited dimensions must preserve prepared chunks")
assert(not old.valid)
local first=storage.canvas[1].objs[1]
C.begin({index=2,force=force},916,668)
assert(first.valid and storage.canvas[2].objs[1].players[1]==2,"drawing another player changed visibility or cleared the first")
C.clear(2)
assert(first.valid,"clearing another player's camera cleared this player")
before=requests
surface.chunks["16,0"]=nil
C.begin(a,916,668)
assert(requests==before+1 and surface.is_chunk_generated({16,0}),"a deleted backing chunk must be generated again")
before=requests
surface.valid=false
surface=make_surface(15)
C.begin(a,916,668)
assert(requests==before+6,"a replacement surface must regenerate every required chunk")
assert(surface.is_chunk_generated({15,-1}) and surface.is_chunk_generated({17,0}))
surface=nil
game.create_surface=function(name,settings)
  assert(name==C.SURFACE and settings.width==0 and settings.height==0,
    "new canvases must explicitly avoid inheriting the saved map's finite dimensions")
  surface=make_surface(16)
  return surface
end
C.begin(a,916,668)
assert(surface.is_chunk_generated({16,0}),"new unlimited canvas did not prepare the player's distant region")
print("CANVAS VISIBILITY PASS: complete chart bounds, cached chunks, per-player isolation, deleted chunks, replacement surfaces and finite-map migration")
