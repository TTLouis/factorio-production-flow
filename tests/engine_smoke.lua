-- Injected only into the isolated test copy, never into the release.
local Geometry = require("scripts.ribbon_geometry")
local Sampler = require('scripts.sampler')
local Canvas = require('scripts.canvas')
local Smoke = {}
function Smoke.run(UI, Canvas)
  local surface = game.surfaces[1]
  -- Runtime 2.1 product probabilities use independent/shared fields. Check a
  -- real probabilistic recipe, rather than allowing an outdated mock to hide it.
  local uranium = assert(prototypes.recipe['uranium-processing'])
  local graph_products = storage.graph.recipes['uranium-processing'].products
  for i, product in ipairs(uranium.products) do
    local probability = product.independent_probability
    assert(probability ~= nil, 'Expected native 2.1 probability field')
    if product.shared_probability then
      probability = probability * (product.shared_probability.max - product.shared_probability.min)
    end
    assert(math.abs(graph_products[i].amount - product.amount * probability) < 1e-12,
      'Graph must preserve native uranium processing probabilities')
  end
  local assembler = assert(surface.create_entity{name='assembling-machine-2',position={0,0},force='player'})
  assembler.set_recipe('iron-gear-wheel')
  local recipe = game.forces.player.recipes['iron-gear-wheel']
  local before = assembler.productivity_bonus
  recipe.productivity_bonus = .25
  log('NATIVE PRODUCTIVITY CONTRACT: ' .. helpers.table_to_json{
    entity_before=before,entity_after=assembler.productivity_bonus,recipe_bonus=recipe.productivity_bonus})
  assert(assembler.productivity_bonus == before,
    'Entity productivity already includes recipe research; sampler would double count')
  recipe.productivity_bonus = 0
  assembler.destroy()
  local deleted = game.create_surface('production-flow-smoke-delete', {width=32,height=32})
  local index = deleted.index
  local machine = assert(deleted.create_entity{name='assembling-machine-2',position={0,0},force='player'})
  Sampler.add(machine)
  local unit = machine.unit_number
  assert(storage.machines[unit], 'Native test machine was not tracked')
  storage.stat_last[index] = {stale=true}
  local test_bin = {rec={[index]={}},stat={[index]={}},coverage={[index]={0,1},[0]={0,1}}}
  storage.bins[-999] = test_bin
  assert(game.delete_surface(deleted), 'Native test surface deletion failed')
  storage.smoke_pending_delete = {surface=index,unit=unit,bin=test_bin,tick=game.tick}
  local original = rendering
  local bad = pcall(function()
    original.draw_polygon { surface = surface, color = { 1, 0, 0 },
      vertices = { { target = { 0, 0 } }, { target = { 1, 0 } }, { target = { 1, 1 } } } }
  end)
  assert(not bad, "Engine must reject the previous crashing vertex format")
  -- --create has no connected player. Remove player visibility filters while
  -- retaining the actual engine implementations and all shape arguments.
  rendering = {
    draw_rectangle = function(a) a.players = nil; return original.draw_rectangle(a) end,
    draw_polygon = function(a) a.players = nil; return original.draw_polygon(a) end,
  }
  local player = { index = 1, force = game.forces.player }
  local painter = Canvas.begin(player, 640, 480)
  for _, t in ipairs({ 1, 6, 120.7 }) do
    for _, delta in ipairs({ -150, 0, 150 }) do
      for _, primitive in ipairs(Geometry.route({ t = t }, 30, 600, 200, 200 + delta)) do
        local object = painter.primitive(primitive, Canvas.col(1))
        assert(object and object.valid, "Engine rejected ribbon primitive")
      end
    end
  end
  for _, corner in ipairs({ "bl", "tr", "tl", "br" }) do
    assert(painter.primitive({ kind = "elbow", corner = corner, k = 16, x = 100, y = 100, w = 40, h = 40 }, Canvas.col(2)).valid)
  end
  local pieces = Geometry.route({ t = 13 }, 30, 600, 200, 100)
  for _, p in ipairs(Geometry.route({ t = 13 }, 600, 1000, 100, 300)) do pieces[#pieces + 1] = p end
  assert(painter.ribbon(pieces, Canvas.col(1)).valid, "Engine rejected complete ribbon mesh")
  Canvas.clear(1)
  local backing = Canvas.surface()
  log('CANVAS NATIVE BOUNDS: '..helpers.table_to_json{width=backing.map_gen_settings.width,
    height=backing.map_gen_settings.height,generated=backing.is_chunk_generated({16,0})})
  assert(backing.map_gen_settings.width==2000000 and backing.map_gen_settings.height==2000000 and
    backing.is_chunk_generated({16,0}), 'Canvas inherited finite factory bounds')
  local chunk={{512,0},{544,32}}
  assert(backing.generate_with_lab_tiles and backing.always_day and backing.freeze_daytime and not backing.show_clouds,
    'Canvas lab generation and lighting settings are missing')
  assert(backing.count_tiles_filtered{area=chunk,name={'lab-dark-1','lab-dark-2','lab-white'}}==1024,
    'Canvas backing chunk contains non-lab tiles')
  assert(#backing.find_entities_filtered{area=chunk}==0 and #backing.find_decoratives_filtered{area=chunk}==0,
    'Canvas generated entities or decoratives')
  local finite=backing.map_gen_settings
  finite.width,finite.height=64,64
  backing.map_gen_settings=finite
  Canvas.begin(player,640,480)
  assert(backing.map_gen_settings.width==2000000 and backing.map_gen_settings.height==2000000,
    'Legacy finite canvas did not expand')
  Canvas.clear(1)
  backing.delete_chunk({16,0})
  storage.smoke_pending_delete.canvas_surface = backing
  rendering = original
  for _, size in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 } }) do
    local w, h = UI.dimensions({ width = size[1], height = size[2] }, 1)
    assert(w < size[1] and h < size[2], "Frame exceeds 16:9 screen")
  end
  log('PRODUCTION FLOW ENGINE SMOKE SETUP OK: native probability/productivity contracts and rendering accepted')
end
function Smoke.verify()
  local pending = storage.smoke_pending_delete
  if not pending or game.tick < pending.tick + 10 then return end
  local index, unit, bin = pending.surface, pending.unit, pending.bin
  assert(not game.surfaces[index] and not storage.machines[unit] and not storage.stat_last[index] and
    not bin.rec[index] and not bin.stat[index] and not bin.coverage[index],
    'Native surface deletion event retained old samples')
  local native=rendering
  rendering={draw_rectangle=function(a) a.players=nil;return native.draw_rectangle(a) end}
  if not pending.canvas_queued then
    local backing=pending.canvas_surface
    assert(not backing.is_chunk_generated({16,0}), 'Native deferred chunk deletion did not occur')
    Canvas.begin({index=1,force=game.forces.player},640,480)
    assert(backing.is_chunk_generated({16,0}), 'Canvas cached a deleted native chunk')
    Canvas.clear(1)
    rendering=native
    assert(game.delete_surface(backing), 'Could not queue native canvas replacement test')
    pending.canvas_queued,pending.tick=true,game.tick
    return
  end
  assert(not pending.canvas_surface.valid, 'Native canvas surface was not deleted')
  local replacement=Canvas.begin({index=1,force=game.forces.player},640,480)
  assert(replacement.surface.is_chunk_generated({16,0}), 'Recreated canvas reused stale chunk cache')
  Canvas.clear(1)
  rendering=native
  storage.bins[-999], storage.smoke_pending_delete = nil, nil
  log('PRODUCTION FLOW ENGINE SMOKE OK: rendering, probabilities, productivity, surface deletion and canvas regeneration')
end
return Smoke
