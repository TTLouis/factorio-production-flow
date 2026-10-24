-- Group resolution (D20): per-player overrides -> default table -> Factorio subgroup fallback.
-- storage.pgroups[player_index] = { assign = {[key] = group_id}, custom = {[group_id] = {name, super}}, next = n }

local Default = require("shared.groups_default")
local palette = require("shared.palette")

local Gr = {}

local function nice(str)
  str = string.gsub(str, "[-_]", " ")
  return string.upper(string.sub(str, 1, 1)) .. string.sub(str, 2)
end

-- Prototype order strings are compared lexically, with names breaking ties.
local function before(a, b)
  if (a.order or "") ~= (b.order or "") then return (a.order or "") < (b.order or "") end
  return a.name < b.name
end

local function rank(proto, all)
  local n = 0
  for _, p in pairs(all or {}) do if before(p, proto) then n = n + 1 end end
  return n
end

-- Some 2.0 subgroup objects do not expose the newer localisation property.
local function localised(proto)
  if not proto then return nil end
  local ok, value = pcall(function() return proto.localised_name end)
  return ok and value or nil
end

function Gr.less(a, b)
  if a.super_order ~= b.super_order then return a.super_order < b.super_order end
  if a.super ~= b.super then return a.super < b.super end
  if a.order ~= b.order then return a.order < b.order end
  return a.id < b.id
end

local function pg(pi)
  storage.pgroups = storage.pgroups or {}
  local s = storage.pgroups[pi]
  if not s then
    s = { assign = {}, custom = {}, next = 1 }
    storage.pgroups[pi] = s
  end
  return s
end
Gr.state = pg

local function hash_color(str)
  local h = 0
  for i = 1, #str do h = (h * 31 + string.byte(str, i)) % 1000003 end
  return h % #palette.colors + 1
end

-- fallback group from the prototype's subgroup
local function fallback(key)
  local t, n = string.match(key, "^(%a+)/(.+)$")
  local proto
  if t == "item" then proto = prototypes.item[n]
  elseif t == "fluid" then proto = prototypes.fluid[n] end
  if t == "item" and string.match(n, "%-barrel$") then return "barrels" end
  if not (proto and proto.subgroup) then return "sub:other" end
  return "sub:" .. proto.subgroup.name
end

-- returns info table {id, name, super, super_name, color, order, super_order}
function Gr.info(pi, id)
  local s = pg(pi)
  local c = s.custom[id]
  if c then
    local sup = Default.supers[c.super]
    local tab_id = string.match(c.super, "^tab:(.+)$")
    local tab = tab_id and prototypes.item_group and prototypes.item_group[tab_id]
    return { id = id, name = c.name, super = c.super, super_name = sup and sup.name or tab and nice(tab.name) or c.super,
             super_localised_name = localised(tab),
             color = sup and sup.color or hash_color(c.super), order = 1000 + (c.order or 0),
             super_order = Default.super_order[c.super] or (tab and 100 + rank(tab, prototypes.item_group)) or 99 }
  end
  local d = Default.groups[id]
  if d then
    local sup = Default.supers[d.super]
    return { id = id, name = d.name, super = d.super, super_name = sup.name, color = sup.color,
             order = Default.group_order[id], super_order = Default.super_order[d.super] }
  end
  local sub = string.match(id, "^sub:(.+)$") or id
  local sg = prototypes.item_subgroup and prototypes.item_subgroup[sub]
  local tab = sg and sg.group
  local super = tab and Default.tab_to_super[tab.name] or "other"
  -- Keep a mod's own crafting-menu tab instead of mixing it into Other.
  if tab and not Default.tab_to_super[tab.name] then super = "tab:" .. tab.name end
  local sup = Default.supers[super]
  return { id = id, name = nice(sub), localised_name = localised(sg),
           super = super, super_name = sup and sup.name or nice(tab.name),
           super_localised_name = not sup and localised(tab) or nil,
           color = sup and sup.color or hash_color(super),
           order = 500 + (sg and rank(sg, prototypes.item_subgroup) or 0),
           super_order = Default.super_order[super] or (100 + rank(tab, prototypes.item_group)) }
end

function Gr.of(pi, key)
  if string.sub(key, 1, 7) == "recipe/" then return "recipes" end
  local s = pg(pi)
  return s.assign[key] or Default.items[key] or fallback(key)
end

function Gr.assign(pi, key, group_id)
  pg(pi).assign[key] = group_id
end

function Gr.unassign(pi, key)
  pg(pi).assign[key] = nil
end

function Gr.create(pi, name, super)
  local s = pg(pi)
  local id = "user-" .. s.next
  s.next = s.next + 1
  s.custom[id] = { name = name, super = super or "other", order = s.next }
  return id
end

-- Defaults, custom groups and prototype subgroups (including modded ones).
function Gr.list(pi)
  local out, seen = {}, {}
  local function add(id)
    if not seen[id] then seen[id] = true; out[#out + 1] = Gr.info(pi, id) end
  end
  for id in pairs(Default.groups) do add(id) end
  for id in pairs(pg(pi).custom) do add(id) end
  for id in pairs(prototypes.item_subgroup or {}) do add("sub:" .. id) end
  for _, id in pairs(pg(pi).assign) do add(id) end
  table.sort(out, Gr.less)
  return out
end

return Gr
