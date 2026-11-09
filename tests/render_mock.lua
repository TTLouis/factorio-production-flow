local player = game.players[1]
local RO = {}
local function object(kind, args)
  local o = { valid = true, k = kind, a = args }
  o.destroy = function() o.valid = false end
  RO[#RO + 1] = o
  return o
end
rendering = {
  draw_rectangle = function(a) return object("rect", a) end,
  draw_line = function(a) return object("line", a) end,
  draw_text = function(a) return object("text", a) end,
  draw_polygon = function(a)
    assert(#a.vertices >= 3, "polygon needs 3+ vertices")
    for _, vertex in ipairs(a.vertices) do
      assert(type(vertex[1]) == "number" and type(vertex[2]) == "number" and not vertex.target,
        "Factorio polygon vertex must be a MapPosition, not {target=...}")
    end
    return object("poly", a)
  end,
}
local SURF
game.get_surface = function(n) return SURF end
game.create_surface = function(n, s) SURF = { index = 77, name = n, request_to_generate_chunks = function() end,
  force_generate_chunk_requests = function() end, set_tiles = function() end }; return SURF end
player.force = player.force or {}
player.force.chart = function() end
game.forces = game.forces or { player = { set_surface_hidden = function() end } }
player.display_scale = player.display_scale or 1

return RO
