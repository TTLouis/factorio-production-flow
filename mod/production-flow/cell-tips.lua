local function simulation(lesson)
  return {
    generate_map = true,
    checkboard = false,
    mods = { "production-flow" },
    mute_alert_sounds = true,
    game_view_settings = { default_show_value = false, show_entity_info = true, update_entity_selection = true },
    init = 'remote.call("production-flow-cell-tips", "start", "' .. lesson .. '")',
    update = 'remote.call("production-flow-cell-tips", "update")',
  }
end

data:extend {
  { type = "tips-and-tricks-item-category", name = "production-flow", order = "z[production-flow]" },
  { type = "tips-and-tricks-item", name = "production-flow", category = "production-flow",
    order = "0", starting_status = "unlocked", is_title = true },
  { type = "tips-and-tricks-item", name = "production-flow-create-cell", category = "production-flow",
    order = "a", starting_status = "unlocked", indent = 1, tag = "[item=electronic-circuit]", simulation = simulation("create") },
  { type = "tips-and-tricks-item", name = "production-flow-subdivision", category = "production-flow",
    order = "b", starting_status = "unlocked", indent = 1, tag = "[item=logistic-science-pack]", simulation = simulation("subdivision") },
  { type = "tips-and-tricks-item", name = "production-flow-train-stop", category = "production-flow",
    order = "c", starting_status = "unlocked", indent = 1, tag = "[item=train-stop]", simulation = simulation("rail") },
  { type = "tips-and-tricks-item", name = "production-flow-chart-modes", category = "production-flow",
    order = "d", starting_status = "unlocked", indent = 1 },
}

if mods["space-age"] then
  data:extend {
    { type = "tips-and-tricks-item", name = "production-flow-space-age-transfers", category = "production-flow",
      order = "e", starting_status = "unlocked", indent = 1, tag = "[item=space-platform-starter-pack]" },
  }
elseif mods["space-exploration"] then
  data:extend {
    { type = "tips-and-tricks-item", name = "production-flow-space-exploration-transfers", category = "production-flow",
      order = "e", starting_status = "unlocked", indent = 1, tag = "[item=rocket-silo]" },
  }
end
