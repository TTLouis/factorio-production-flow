# In-game UI style rules

Production Flow should look like part of Factorio. Every window, button and label
uses a vanilla style from `data.raw["gui-style"].default`, so it keeps the base
game's graphics, hover glow, click sound and GUI-scale behaviour. Follow these
rules for any GUI change, and check native screenshots afterwards
([development.md](development.md)).

The vanilla definitions are in the installed game at
`Factorio/data/core/prototypes/style.lua` (styles) and
`Factorio/data/core/prototypes/utility-sprites.lua` (`utility/*` icons). Read
them when unsure; the names below were checked against Factorio 2.1.

## How the base game builds a window

```
frame                                   (default "frame" style, direction vertical)
├─ flow  title bar                      (drag_target = the frame)
│   ├─ label           "frame_title"
│   ├─ empty-widget    "draggable_space_header"   horizontally stretchable, height 24
│   └─ sprite-button   "frame_action_button"      utility/close, utility/search, ...
├─ frame "inside_shallow_frame" / "inside_deep_frame"   the content panel
│   ├─ frame "subheader_frame"          toolbar strip across the top of the panel
│   │   ├─ label "subheader_caption_label"
│   │   ├─ empty-widget (stretch)
│   │   └─ sprite-button "tool_button" ...        right-aligned actions
│   └─ content (tables, scroll panes, slot grids in "slot_button_deep_frame")
└─ flow "dialog_buttons_horizontal_flow"           only for dialogs
    ├─ button "back_button"    left   (Cancel / Back)
    ├─ empty-widget "draggable_space" (stretch)
    └─ button "confirm_button" right  (Confirm / Apply)
```

Panels sit flush in the outer frame. Spacing comes from the styles, which use
multiples of 4 px (`default_container_spacing = 4`); there is no need to add
margins to line panels up.

## Vanilla button catalogue

| Style | Look | Size | Base game uses it for |
| --- | --- | --- | --- |
| `frame_action_button` | Dark square, the icon inverts on hover | 24×24 | Title-bar actions: close, search, pin, help |
| `tool_button` | Light square with an icon, orange glow on hover | 28 high, ≥28 wide | Toolbar and row actions (edit, rename, copy, refresh) |
| `tool_button_red` | Red square | 28×28 | Destructive row actions (delete, flush fluid, trash) |
| `tool_button_green` | Green square | 28 high | Positive or confirm actions inside a toolbar |
| `tool_button_blue` | Blue square | 28 high | Rare; a special or alternative mode |
| `mini_button` / `mini_tool_button_red` | Small square | 16×16 | Tiny actions next to text, such as remove-from-list |
| `slot_button` | Dark inset slot | 40×40 | An item, fluid, recipe or signal the player can click |
| `choose-elem-button` (element type) | Slot with a picker | 40×40 | Choosing an item, fluid, recipe or signal |
| `confirm_button` | Green, arrow pointing right | 32 high, ≥112 | The main confirm in a dialog's bottom row |
| `back_button` / `forward_button` | Grey, arrow pointing left / right | 32 high | Cancel or back, next, in a dialog's bottom row |
| `red_confirm_button` / `red_back_button` | Red arrow | 32 high | A confirm or back that discards or deletes |
| `green_button` / `red_button` | Coloured wide text button | 28 high, ≥108 | Text commands with a clear positive or destructive meaning |
| `button` (default) | **Plain light-grey text button** | 28 high, ≥108 | Neutral text commands, almost always in a dialog row |
| `mod_gui.button_style` (`mod_gui_button`) | Square | 40×40 | The mod's button in the top-left mod button flow |

Selected and pressed states are built into these styles. Set
`element.toggled = true` on a `sprite-button` (or `button`) to show it as
on/selected. Every button style also carries its click sound (`gui-tool-button`,
`gui-green-confirm`, `gui-red-button`), so picking the right style also gives the
right sound.

## Colour language

| Colour | Meaning |
| --- | --- |
| Orange glow (`default_glow_color`) | Hover on any clickable control. It comes from the style; never fake it. |
| Light / grey body | Neutral action |
| Green | Confirm, apply, positive. Base game confirm buttons are green. |
| Red | Destructive or discarding: delete, reset, clear |
| Pressed / selected graphics | A toggle that is on, the selected tab, the selected row |
| `gui_color.caption` {255, 230, 192} | Titles and headings (the `frame_title`, `heading_2_label` and `caption_label` styles) |
| `gui_color.grey` {0.5, 0.5, 0.5} | Secondary text (`grey_label`) |
| `gui_color.blue` {128, 206, 240} | Tips and information (`info_label`) |
| `gui_color.red` {255, 142, 142} | Errors and warnings (`red_label`) |

## Frames, labels and other controls

| Need | Vanilla style |
| --- | --- |
| Window title | `frame_title` |
| Toolbar strip at the top of a panel | `subheader_frame` (repeated strips in a list: `repeated_subheader_frame`) |
| Text in a toolbar strip | `subheader_caption_label`, `subheader_semibold_label` |
| Section heading in a panel | `caption_label` or `heading_2_label` |
| Emphasis | `bold_label`, `semibold_label` |
| Secondary hint text | `grey_label` (the existing `hint()` helper keeps its small grey font) |
| Content panel | `inside_shallow_frame`, `inside_shallow_frame_with_padding`, `inside_deep_frame` |
| Grid of item slots | `slot_button_deep_frame` holding a table of `slot_button`s |
| Scroll area inside a panel | `naked_scroll_pane` (the panel draws the border) |
| Pick one of a few options | `drop-down`, `radiobutton`, or a `switch` for two states |
| On/off setting | `checkbox` |
| Separator | `line` |

## Rules for this mod

### Buttons

1. **Do not add a plain grey `button` for a toolbar or row action.** An unstyled
   `type = "button"` is the default light-grey text button. In the base game that
   button only appears in dialog rows. In toolbars, title bars, subheaders and
   table rows use an icon button instead:
   - title bar → `sprite-button`, style `frame_action_button`
   - toolbar, subheader or row action → `sprite-button`, style `tool_button`
   - destructive action → `tool_button_red` (or `red_button` when it needs text)
   - confirm or apply → `tool_button_green`, `green_button`, or `confirm_button`
     in a dialog row
   - item, fluid or recipe → `slot_button` or `choose-elem-button`
2. **Use vanilla `utility/*` sprites for icons.** Useful ones that exist in 2.1:
   `close`, `search`, `refresh`, `reset`, `trash`, `add`, `copy`, `rename_icon`,
   `expand`, `collapse`, `left_arrow`, `right_arrow`, `down_arrow`,
   `backward_arrow`, `forward_arrow`, `go_to_arrow`, `center`, `pin_arrow`,
   `filter_blacklist`, `list_view`, `grid_view`, `questionmark`, `check_mark`,
   `play`, `pause`, `speed_up`, `speed_down`. Core utility sprites are always
   present, so do not write fallbacks to text glyphs such as `"X"` or `">"`.
3. **No text glyphs as fake icons.** Captions such as `X`, `>`, `◀`, `▲`, `▼`,
   `+` or `−` on a shrunken grey button do not match the game. Use the sprite. If
   vanilla has no fitting sprite (zoom in and out, Fit), use a `tool_button` with
   that glyph or one short word as its caption, so it is at least a vanilla 28 px
   tool button. Do not borrow an icon that means something else (`expand` reads
   as "next", not "fit").
4. **Every icon-only button has a tooltip** that names the action and any
   modifier (for example "Shift: to top").
5. **A toggle shows its state with `toggled`**, not with a changing caption such
   as "Ordering: on" or "Advanced" / "Less". For settings, prefer a `checkbox`;
   for two-way modes, a `switch` or `drop-down`.
6. **Size comes from the style.** Keep `tool_button` at 28 px in toolbars. Inside
   dense table rows it may be reduced to 24×24 to fit the row height (the Balance
   row inspect and star buttons do this). Do not set widths on text buttons to
   squeeze them; if text does not fit, it should be an icon.
7. **Text buttons are for dialogs and long-form commands only.** When text is
   unavoidable (for example "Show 200 more" at the end of a list), use the vanilla
   style that matches its meaning and place it where the base game would: at the
   bottom of the list or in a `dialog_buttons_horizontal_flow`.

### Styles and colours

8. **Custom styles must have a vanilla `parent`** and may only change size,
   padding, margins, spacing, alignment or table line colours. Do not replace
   `graphical_set`s, hover glows or font colours on buttons.
9. **Use vanilla label styles for text colour.** Do not hard-code new
   `font_color`s. The established exceptions are the Balance status colours and
   the existing grey `hint()` helper; reuse those rather than adding more.
10. **Custom graphics only when vanilla has nothing suitable.** Prefer pointing a
    sprite prototype at a base-game image. The Balance favourite star
    (`ssk-star`, `ssk-star-off`) does this: it uses the Browse Games star from
    `__core__/graphics/gui-new.png` inside a `tool_button`. The chart settings
    gear (`ssk-gear`) is a 32 px crop of the side-menu gear from
    `__core__/graphics/side-menu-buttons.png`, tinted dark because the original
    is drawn light for dark buttons.
11. **Developer detail stays behind the "Show development tools" setting.** Chart
    statistics, scan cadence, machine counts and legend lines that Help already
    explains are hidden from normal players.

### Layout

12. Build windows with the anatomy above: `frame_title` + `draggable_space_header`
    + `frame_action_button`s, content in `inside_deep_frame` or
    `inside_shallow_frame`, toolbars in `subheader_frame`s.
13. Right-align toolbar actions after a stretching `empty-widget`, as the base game
    does. Group related controls; do not mix text buttons, drop-downs and icon
    buttons at random widths in one row.
14. Do not rely on Unicode symbols rendering in the default fonts; test them in
    native screenshots.
15. A chart and its controls form one panel, not loose pieces on the tab
    background: an `inside_deep_frame` with every toolbar row in one
    `subheader_frame` across its top and the chart in a `naked_scroll_pane`
    directly below (Balance, Focus and Full Sankey all do this). The strip uses
    the same spacing on every tab: 12 px left/right and 8 px top/bottom padding,
    a 40 px first row (fits a slot button), 28 px rows after it and 8 px between
    rows (`toolbar_strip` in `sankey_ui.lua`).
16. Less-used chart settings open from a gear `tool_button` (toggled while open)
    as a fly-out: a `frame` with a `frame_title`, a `frame_action_button` close
    and an `inside_shallow_frame_with_padding`, drawn over the chart's top-right
    corner. It takes no layout height, so the chart never moves. Clicking the
    gear again, the close button or Esc closes it; so do tab changes and
    reopening the window.
17. The item/fluid picker copies the base game's item selector: the search field
    (`search_popup_textfield`) and a `utility/search` button in the title bar,
    six `filter_group_button_tab_slightly_larger` group tabs per row (square,
    71 px like the vanilla filter tab's width; further groups wrap onto a new
    row), and a ten-column `filter_slot_table` in a `deep_slots_scroll_pane` inside
    a `filter_frame`, padded so the grid and scrollbar match the tab row's
    width. Mods may add any number of item groups: tabs wrap six per row, and
    past four rows the tab area scrolls so the grid keeps its space. The grid
    stays ten wide and takes the remaining screen height (4 to 12 rows). While
    searching, groups without a match are disabled.

## Known exceptions to fix

These predate the rules and are developer tools only. Fix them when that code is next touched, one area at a
time, and re-run the native screenshot phases. Do not change the Sankey drawing
code to do so; only the toolbar controls around it.

| Where | Today | Should become |
| --- | --- | --- |
| Graph and Sampler tabs ("Rebuild graph", "Rescan machines") | Plain grey `button` | `tool_button` with `utility/refresh` (developer tools; low priority) |
| Render test window toolbar | Cycling text buttons ("Switch to …", "Ordering: on") | `drop-down`/`checkbox` (developer tool; low priority) |

The chart toolbars, Balance footer, close buttons and favourite star were
brought in line in October 2026. "Show 200 more" remains the one deliberate
text button, centred under the Balance list.

## Checklist for a UI change

- No new unstyled `type = "button"` outside a dialog row.
- Every `sprite-button` has a vanilla style, a `utility/*` (or prototype) sprite
  and a tooltip.
- Toggles use `toggled`; destructive actions are red; confirms are green.
- Any new custom style has a vanilla parent and changes only layout properties.
- `python tests/run_lua.py` passes, and native screenshots at the relevant GUI
  scales show no clipping, overlap or misaligned rows.
