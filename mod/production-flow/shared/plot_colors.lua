-- Existing plot colours, also used to tint GUI rectangles outside world-camera
-- postprocessing (notably modded night vision).
return {
  background={r=.16,g=.16,b=.17,a=1}, grid={r=.34,g=.34,b=.35,a=1},
  incoming={r=.40,g=.67,b=.90,a=1}, outgoing={r=.92,g=.58,b=.30,a=1},
  selected={r=.28,g=.24,b=.18,a=.35},
  measured={r=181/255,g=203/255,b=222/255,a=1},
  estimated={r=67/255,g=106/255,b=126/255,a=1},
  outline={r=82/255,g=97/255,b=109/255,a=1},
  receipt={r=139/255,g=212/255,b=156/255,a=1},
  history_grid={.25,.25,.26,1}, history_axis={.56,.54,.52,1},
  history_made={112/255,224/255,164/255,1}, history_used={1,79/255,89/255,1},
  history_surplus={100/255,245/255,114/255,1},
  history_use_one={202/255,131/255,84/255,1}, history_use_two={191/255,160/255,90/255,1},
  history_use_three={157/255,92/255,89/255,1}, history_other={99/255,112/255,130/255,1},
  history_hover={.15,.12,.06,.24},
  platform_loaded={.28,.59,.73,1}, platform_made={.55,.82,.65,1},
  platform_axis={.49,.48,.46,1}, platform_tick={.75,.74,.71,1}, platform_selection={.28,.24,.18,1},
}
