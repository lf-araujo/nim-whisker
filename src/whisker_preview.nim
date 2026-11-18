## Standalone preview of the menu window, for development without touching
## the panel. The menu opens centered and the program exits when it closes.
##
## Usage: whisker-preview [--stay] [--keep] [--base:PROPERTY_BASE] [--search:TEXT]
##
## --stay    keep the menu open when it loses focus
## --keep    keep running after the menu closes (for tests that check what it
##           did on the way out, such as the clipboard)
## --base    read favorites and recent from this xfce4-panel property base
##           (e.g. /plugins/plugin-5); nothing is ever written back
## --search  open with TEXT typed into the search entry

import std/[parseopt, strutils]
import whisker/[glib, gtk, menuwindow, store]

proc onHide(window: GtkWidget, data: pointer) {.cdecl.} =
  gtk_main_quit()

proc main() =
  var
    stay, keep = false
    base, searchText: string
  for kind, key, value in getopt():
    if kind == cmdLongOption:
      case key.normalize()
      of "stay": stay = true
      of "keep": keep = true
      of "base": base = value
      of "search": searchText = value
      else: quit("unknown option --" & key)

  gtk_init(nil, nil)
  let menu = newMenuWindow(newStore(base, readOnly = true))
  menu.stayOnFocusOut = stay
  if not keep:
    g_signal_connect(menu.window, "hide", cast[GCallback](onHide))
  menu.show()
  if searchText.len > 0:
    menu.setSearchText(searchText)
  gtk_main()

main()
