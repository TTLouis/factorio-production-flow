local Loc = require("scripts.locale")
-- Stable, player-local help; sampling and automatic refresh do not rebuild it.
local H={}
local NAME="ssk_help"
local topics={
  {name=Loc("help-start-here"),sections={
    {Loc("help-open-and-inspect"), Loc("help-open-production-flow-with-its-flow-chart")},
    {Loc("help-periods-and-updates"), Loc("help-choose-1m-10m-1h-10h-50h-250h")},
    {Loc("help-material-selection-and-navigation"), Loc("help-in-balance-and-focus-click-the-material")},
    {Loc("help-a-stable-item-list"), Loc("help-rows-stay-in-place-while-values-change")},
    {Loc("help-favourites"), Loc("help-click-the-star-beside-a-row-s")},
    {Loc("help-material-names-and-recipes"), Loc("help-chart-nodes-use-item-and-fluid-names")},
    {Loc("help-work-in-progress"), Loc("help-balance-is-the-main-focus-of-this")},
  }},
  {name=Loc("help-numbers-stock"),sections={
    {Loc("help-history-warm-up"), Loc("help-recording-begins-when-the-mod-is-installed")},
    {Loc("help-made-used-and-net"), Loc("help-made-and-used-are-measured-changes-in")},
    {Loc("help-reading-a-material-s-history"), Loc("help-rate-history-shows-the-green-made-line")},
    {Loc("help-selected-material-consumption"), Loc("help-the-uses-heading-names-the-selected-material")},
    {Loc("help-chest-stock"), Loc("help-stock-reads-physical-contents-of-ordinary-and")},
    {Loc("help-sampling-and-scope"), Loc("help-chest-reads-are-spread-across-ticks-only")},
    {Loc("help-stock-changes-and-empty-time"), Loc("help-stock-trend-uses-up-to-seven-completed")},
    {Loc("help-chest-stock-in-history"), Loc("help-light-blue-bars-show-completed-chest-scans")},
  }},
  {name=Loc("help-alerts-charts"),sections={
    {Loc("help-material-watches"), Loc("help-star-a-material-or-its-group-and")},
    {Loc("help-machine-status"), Loc("help-use-the-map-icon-in-focus-or")},
    {Loc("help-alerts-are-hints"), Loc("help-balance-groups-activity-counts-under-underproducing-ok")},
    {Loc("help-utilisation"), Loc("help-estimated-utilisation-compares-recorded-normal-crafts-with")},
    {Loc("help-links-versus-totals"), Loc("help-recipe-links-are-estimated-from-completed-crafts")},
    {Loc("help-widths-colors-and-navigation"), Loc("help-compressed-widths-use-a-square-root-scale")},
    {Loc("help-scope"), Loc("help-balance-focus-and-full-sankey-each-cover")},
  }},
  {name=Loc("help-transfers"),sections={
    {Loc("help-flow"), Loc("help-select-a-space-platform-to-see-where")},
    {Loc("help-history"), Loc("help-the-upper-lane-shows-pods-delivered-to")},
    {Loc("help-recording-limits"), Loc("help-transfers-retains-observed-deliveries-for-up-to")},
  }},
}
function H.close(player)
  local f=player.gui.screen[NAME]
  if f then f.destroy() end
end
function H.open(player)
  H.close(player)
  local res,scale=player.display_resolution,player.display_scale
  local W=math.min(900,math.floor(res.width/scale)-60)
  local height=math.min(740,math.floor(res.height/scale)-90)
  local f=player.gui.screen.add{type="frame",name=NAME,direction="vertical"}
  f.style.width,f.style.height=W,height
  local header=f.add{type="flow",direction="horizontal"}
  header.drag_target=f
  header.style.vertical_align="center"
  header.add{type="label",caption=Loc("help-production-flow-help"),style="frame_title",ignored_by_interaction=true}
  local drag=header.add{type="empty-widget",style="draggable_space_header",ignored_by_interaction=true}
  drag.style.horizontally_stretchable=true;drag.style.height=24
  -- Same close control as the main window's title bar.
  header.add{type="sprite-button",style="frame_action_button",sprite="utility/close",tooltip=Loc("help-close"),tags={ssk_ui="help_close"}}
  local inner=f.add{type="frame",name="ssk_help_inner",style="inside_deep_frame",direction="vertical"}
  inner.style.horizontally_stretchable=true;inner.style.vertically_stretchable=true
  local tabs=inner.add{type="tabbed-pane",name="ssk_help_tabs"}
  tabs.style.horizontally_stretchable=true;tabs.style.vertically_stretchable=true
  for i,topic in ipairs(topics) do
    local tab=tabs.add{type="tab",caption=topic.name}
    local scroll=tabs.add{type="scroll-pane",name=Loc.join("ssk_help_topic_", i),
      horizontal_scroll_policy="never",vertical_scroll_policy="auto"}
    scroll.style.width=W-36;scroll.style.height=height-110
    local body=scroll.add{type="flow",direction="vertical"}
    body.style.vertical_spacing=10
    for _,section in ipairs(topic.sections) do
      body.add{type="label",caption=section[1],style="caption_label"}
      local text=body.add{type="label",caption=section[2]}
      text.style.single_line=false;text.style.width=W-70
    end
    tabs.add_tab(tab,scroll)
  end
  f.auto_center=true
  -- Keep the main frame as the opened GUI. Switching player.opened here
  -- raises on_gui_closed for it and can close both windows in the engine.
  if f.bring_to_front then f.bring_to_front() end
  return f
end
return H
