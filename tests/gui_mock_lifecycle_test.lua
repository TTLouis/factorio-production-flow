-- The native GUI invalidates every descendant when a container is cleared or
-- destroyed. Retained references must detect that, including nested chart hits.
return function(make_root)
  local inserted=make_root()
  local left=inserted.add{type="flow",name="left"}
  local right=inserted.add{type="flow",name="right"}
  local middle=inserted.add{type="flow",name="middle",index=2}
  assert(inserted.children[1]==left and inserted.children[2]==middle and inserted.children[3]==right,
    "indexed add must insert beside retained overlays")
  assert(middle.get_index_in_parent()==2 and right.get_index_in_parent()==3)
  middle.destroy()
  assert(right.get_index_in_parent()==2,"parent index must track sibling removal")
  inserted.destroy()
  for _, use_methods in ipairs({ false, true }) do
    local root = make_root()
    local container = root.add { type = "flow", name = "container" }
    local sibling = root.add { type = "flow", name = "sibling" }
    local child = container.add { type = "flow", name = "child" }
    local grandchild = child.add { type = "sprite", name = "hit" }
    local second = container.add { type = "label", name = "second" }

    if use_methods then getmetatable(container).clear(container)
    else container.clear() end
    assert(container.valid and root.valid and sibling.valid,
      "clearing children invalidated their parent or sibling")
    assert(not child.valid and not grandchild.valid and not second.valid,
      "clear must invalidate the complete subtree")
    assert(#container.children == 0 and root.container == container
      and root.sibling == sibling, "clear must retain the container in its parent")

    child = container.add { type = "flow", name = "replacement" }
    grandchild = child.add { type = "sprite", name = "replacement_hit" }
    if use_methods then getmetatable(container).destroy(container)
    else container.destroy() end
    assert(not container.valid and not child.valid and not grandchild.valid,
      "destroy must invalidate the element and complete subtree")
    assert(root.valid and sibling.valid and #root.children == 1
      and root.children[1] == sibling and root.container == nil,
      "destroy must detach only its own subtree")

    root.destroy()
    assert(not root.valid and not sibling.valid, "destroying a root must invalidate its children")
  end
  print("GUI MOCK LIFECYCLE OK: recursive invalidation and sibling isolation")
end
