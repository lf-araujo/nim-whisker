## The menu popup: search entry, session commands, category row and the
## launcher icon views. Ported from upstream `window.cpp`, `page.cpp`,
## `favorites-page.cpp`, `recent-page.cpp` and `launcher-icon-view.cpp`.
##
## Only one layout is built, the one in `config.nim`: categories as an
## icon-only row above the launchers, commands beside the search entry, no
## profile picture, icon view. Not ported yet: resizing by dragging the
## edges, drag and drop, the tree and list views.

import std/[os, strutils]
import ./[apps, commands, config, elements, filematch, filesearch, glib, gtk,
  iconrenderer, search, store, xfce]

type
  PageKind = enum
    pkFavorites, pkRecent, pkApplications, pkSearch
  ActionEntry = object ## One thing that can be done with the selected item.
    icon, label: string ## `icon` is an icon name or a serialized GIcon.
    enabled, opensPage: bool ## `opensPage`: runs another page of actions.
    run: proc () {.closure.}
  ActionPage = object ## What the actions panel shows.
    icon, title, subtitle: string
    entries: seq[ActionEntry]
    selected: int ## Remembered while another page is on top of this one.
  Section = enum ## The parts of the search page, top to bottom.
    secApps, secSettings, secFiles
  Move = enum
    mvUp, mvDown, mvLeft, mvRight
  PositionProc* = proc (data: pointer, window: GtkWidget, x, y: var cint)
    {.nimcall.}
  MenuWindow* = ref object
    window*: GtkWidget
    searchEntry, contentsStack, panelsStack, categoryButtons: GtkWidget
    message: GtkWidget
    views: array[PageKind, GtkWidget]
    pageButtons: array[pkFavorites .. pkApplications, GtkWidget]
    categoryWidgets: seq[GtkWidget]
    commandButtons: seq[GtkWidget]
    apps: AppList
    store: Store
    search: Search
    actionsBox, actionsIcon, actionsTitle, actionsSubtitle: GtkWidget
    actionsList, actionsScroll: GtkWidget
    actionRows: seq[GtkWidget]
    actionPages: seq[ActionPage] ## Open pages; the last one is shown.
    actionsReturn: string ## Stack page to go back to when the panel closes.
    searchPane: GtkWidget ## Scrolled container of the search grid.
    settingsBox, settingsList: GtkWidget
    settingRows: seq[GtkWidget]
    settingItems: seq[Element] ## Launchers of the rows in `settingsList`.
    files: FileSearch
    filesBox, filesList: GtkWidget
    fileRows: seq[GtkWidget]
    filePaths: seq[string] ## Paths of the rows in `filesList`, in order.
    resultsMode: bool ## Left/Right move through results, not the text.
    gridColumn: int ## Grid column to return to when moving back up.
    childHasFocus: bool
    supportsAlpha: bool
    geometry, monitor: GdkRectangle
    stayOnFocusOut*: bool
    attachWidget*: GtkWidget ## Panel button; picks the monitor to open on.
    positionAt*: PositionProc ## Places the window; unset centers it.
    onClosed*: proc (data: pointer) {.nimcall.} ## Closed other than by
                                                ## losing focus.
    hostData*: pointer

const
  textColumn = 1
  tooltipColumn = 2
  pageKey = "whisker-page"
  categoryKey = "whisker-category"
  pageNames: array[pkFavorites .. pkApplications, cstring] = [
    cstring"favorites", "recent", "applications"]

proc toMenu(data: pointer): MenuWindow = cast[MenuWindow](data)

proc clearSettings(menu: MenuWindow) # Defined with the settings results.
proc closeActions(menu: MenuWindow) # Defined with the actions panel.

# --- Launcher views ---------------------------------------------------------

proc setItems(view: GtkWidget, items: openArray[Element]) =
  var types = [g_icon_get_type(), G_TYPE_STRING, G_TYPE_STRING,
    G_TYPE_POINTER]
  let model = gtk_list_store_newv(cint(types.len), addr types[0])
  for element in items:
    gtk_list_store_insert_with_values(model, nil, high(cint),
        cint(0), element.icon, cint(textColumn), cstring(element.text),
        cint(tooltipColumn), cstring(element.tooltip),
        cint(elementColumn), cast[pointer](element), cint(-1))
  gtk_icon_view_set_model(view, model)
  g_object_unref(model)

proc elementAt(view: GtkWidget, path: GtkTreePath): Element =
  let model = gtk_icon_view_get_model(view)
  var
    iter: GtkTreeIter
    element: pointer
  if model != nil and gtk_tree_model_get_iter(model, addr iter, path) != 0:
    gtk_tree_model_get(model, addr iter, cint(elementColumn), addr element,
        cint(-1))
    result = cast[Element](element)

proc hasSelection(view: GtkWidget): bool =
  let selection = gtk_icon_view_get_selected_items(view)
  result = selection != nil
  var node = selection
  while node != nil:
    gtk_tree_path_free(cast[GtkTreePath](node.data))
    node = node.next
  g_list_free(selection)

proc scrollToTop(view: GtkWidget) =
  let adjustment = gtk_scrollable_get_vadjustment(view)
  gtk_adjustment_set_value(adjustment, gtk_adjustment_get_lower(adjustment))

proc selectFirst(view: GtkWidget) =
  let model = gtk_icon_view_get_model(view)
  var iter: GtkTreeIter
  if model != nil and gtk_tree_model_get_iter_first(model, addr iter) != 0:
    let path = gtk_tree_model_get_path(model, addr iter)
    gtk_icon_view_set_cursor(view, path, nil, 0)
    gtk_icon_view_select_path(view, path)
    gtk_icon_view_scroll_to_path(view, path, 1, 0.5, 0.5)
    gtk_tree_path_free(path)
  scrollToTop(view)

proc resetSelection(view: GtkWidget) =
  ## Puts the keyboard cursor on the first item with nothing highlighted.
  selectFirst(view)
  gtk_icon_view_unselect_all(view)

# --- Search page cursor -----------------------------------------------------
# The search page has three sections: the application grid, the Settings list
# and the Files list. Exactly one item across them is selected (highlighted)
# and that selection is the keyboard cursor. Keyboard focus itself stays in
# the search entry, so typing always works; the arrow keys just move the
# selection from section to section.

proc freePaths(list: ptr GList) =
  var node = list
  while node != nil:
    gtk_tree_path_free(cast[GtkTreePath](node.data))
    node = node.next
  g_list_free(list)

proc searchView(menu: MenuWindow): GtkWidget = menu.views[pkSearch]

proc listOf(menu: MenuWindow, section: Section): GtkWidget =
  if section == secSettings: menu.settingsList else: menu.filesList

proc sectionLen(menu: MenuWindow, section: Section): int =
  case section
  of secApps:
    let model = gtk_icon_view_get_model(menu.searchView)
    if model != nil:
      result = int(gtk_tree_model_iter_n_children(model, nil))
  of secSettings: result = menu.settingRows.len
  of secFiles: result = menu.fileRows.len

proc selectedIndex(menu: MenuWindow, section: Section): int =
  ## Index of the selected item in `section`, or -1.
  result = -1
  if section == secApps:
    let selection = gtk_icon_view_get_selected_items(menu.searchView)
    if selection != nil:
      let indices = gtk_tree_path_get_indices(
          cast[GtkTreePath](selection.data))
      if indices != nil:
        result = int(indices[])
      freePaths(selection)
  else:
    let row = gtk_list_box_get_selected_row(menu.listOf(section))
    if row != nil:
      result = int(gtk_list_box_row_get_index(row))

proc cursor(menu: MenuWindow): tuple[section: Section, index: int] =
  ## The selected item of the search page; `index` is -1 when none is.
  for section in Section:
    let index = menu.selectedIndex(section)
    if index >= 0:
      return (section, index)
  (secApps, -1)

proc setCursor(menu: MenuWindow, section: Section, index: int) =
  ## Selects exactly one item on the search page and scrolls it into view.
  if index < 0 or index >= menu.sectionLen(section):
    return
  if section != secApps:
    gtk_icon_view_unselect_all(menu.searchView)
  if section != secSettings:
    gtk_list_box_unselect_all(menu.settingsList)
  if section != secFiles:
    gtk_list_box_unselect_all(menu.filesList)
  case section
  of secApps:
    let path = gtk_tree_path_new_from_indices(cint(index), cint(-1))
    gtk_icon_view_set_cursor(menu.searchView, path, nil, 0)
    gtk_icon_view_select_path(menu.searchView, path)
    gtk_icon_view_scroll_to_path(menu.searchView, path, 1, 0.5, 0.5)
    gtk_tree_path_free(path)
  of secSettings:
    gtk_list_box_select_row(menu.settingsList, menu.settingRows[index])
  of secFiles:
    gtk_list_box_select_row(menu.filesList, menu.fileRows[index])

proc selectFirstResult(menu: MenuWindow) =
  ## Selects the first item of the first section that has any.
  for section in Section:
    if menu.sectionLen(section) > 0:
      menu.setCursor(section, 0)
      return

proc gridColumns(menu: MenuWindow): int =
  ## Items per row of the application grid (as currently laid out).
  let count = menu.sectionLen(secApps)
  result = 0
  while result < count:
    let path = gtk_tree_path_new_from_indices(cint(result), cint(-1))
    let row = gtk_icon_view_get_item_row(menu.searchView, path)
    gtk_tree_path_free(path)
    if row != 0:
      break
    inc result
  result = max(1, result)

proc neighbour(menu: MenuWindow, section: Section, step: int): int =
  ## The nearest section above (-1) or below (+1) with items, or -1.
  var ordinal = ord(section) + step
  while ordinal in 0 .. ord(high(Section)):
    if menu.sectionLen(Section(ordinal)) > 0:
      return ordinal
    ordinal += step
  -1

proc moveCursor(menu: MenuWindow, move: Move): bool =
  ## Moves the selection one step; false if there was nowhere to go.
  let (section, index) = menu.cursor
  if index < 0:
    menu.selectFirstResult()
    return true
  let count = menu.sectionLen(section)
  case section
  of secApps:
    let columns = menu.gridColumns
    case move
    of mvLeft:
      if index > 0:
        menu.setCursor(secApps, index - 1)
        result = true
    of mvRight:
      if index + 1 < count:
        menu.setCursor(secApps, index + 1)
        result = true
    of mvUp:
      if index >= columns:
        menu.setCursor(secApps, index - columns)
        result = true
    of mvDown:
      if index + columns < count:
        menu.setCursor(secApps, index + columns)
        result = true
      elif index div columns < (count - 1) div columns:
        # A row below exists but is shorter: go to its last item.
        menu.setCursor(secApps, count - 1)
        result = true
      else:
        let next = menu.neighbour(secApps, +1)
        if next >= 0:
          menu.gridColumn = index mod columns # Up returns to this column.
          menu.setCursor(Section(next), 0)
          result = true
  of secSettings, secFiles:
    case move
    of mvUp:
      if index > 0:
        menu.setCursor(section, index - 1)
        result = true
      else:
        let previous = menu.neighbour(section, -1)
        if previous == ord(secApps):
          let
            columns = menu.gridColumns
            total = menu.sectionLen(secApps)
            lastRow = (total - 1) div columns * columns
          menu.setCursor(secApps, min(lastRow + menu.gridColumn, total - 1))
          result = true
        elif previous >= 0:
          menu.setCursor(Section(previous), menu.sectionLen(Section(previous)) - 1)
          result = true
    of mvDown:
      if index + 1 < count:
        menu.setCursor(section, index + 1)
        result = true
      else:
        let next = menu.neighbour(section, +1)
        if next >= 0:
          menu.setCursor(Section(next), 0)
          result = true
    of mvLeft, mvRight:
      discard

proc hoverSearch(menu: MenuWindow, x, y: cdouble) =
  ## The pointer moved over the grid: the item under it becomes the cursor.
  let path = gtk_icon_view_get_path_at_pos(menu.searchView, cint(x), cint(y))
  if path != nil:
    let indices = gtk_tree_path_get_indices(path)
    if indices != nil and menu.selectedIndex(secApps) != int(indices[]):
      menu.setCursor(secApps, int(indices[]))
    gtk_tree_path_free(path)

proc selectAt(view: GtkWidget, x, y: cdouble) =
  ## Hover selection on the plain pages: the item under the pointer, or
  ## nothing between items.
  let path = gtk_icon_view_get_path_at_pos(view, cint(x), cint(y))
  if path == nil:
    gtk_icon_view_unselect_all(view)
  else:
    if gtk_icon_view_path_is_selected(view, path) == 0:
      gtk_icon_view_set_cursor(view, path, nil, 0)
      gtk_icon_view_select_path(view, path)
    gtk_tree_path_free(path)

proc onViewLeave(view: GtkWidget, event: GdkEvent, data: pointer): gboolean
    {.cdecl.} =
  # On the search page the selection is the keyboard cursor: it stays.
  if data == nil or view != data.toMenu.searchView:
    gtk_icon_view_unselect_all(view)

proc onViewPointer(view: GtkWidget, event: GdkEvent, data: pointer): gboolean
    {.cdecl.} =
  ## Hover selection, for both motion and scroll events.
  var x, y: cdouble
  if gdk_event_get_coords(event, addr x, addr y) != 0:
    if data != nil and view == data.toMenu.searchView:
      data.toMenu.hoverSearch(x, y)
    else:
      selectAt(view, x, y)

# --- Pages ------------------------------------------------------------------

proc activePage(menu: MenuWindow): PageKind =
  if $gtk_stack_get_visible_child_name(menu.contentsStack) == "search":
    pkSearch
  elif gtk_toggle_button_get_active(menu.pageButtons[pkFavorites]) != 0:
    pkFavorites
  elif gtk_toggle_button_get_active(menu.pageButtons[pkRecent]) != 0:
    pkRecent
  else:
    pkApplications

proc launchersFor(menu: MenuWindow, desktopIds: seq[string]): seq[Element] =
  for id in desktopIds:
    let launcher = menu.apps.find(id)
    if launcher != nil:
      result.add launcher

proc refreshFavorites(menu: MenuWindow) =
  menu.views[pkFavorites].setItems(menu.launchersFor(menu.store.favorites))

proc refreshRecent(menu: MenuWindow) =
  menu.views[pkRecent].setItems(menu.launchersFor(menu.store.recent))

proc searchOrder(menu: MenuWindow): seq[Element] =
  ## Recent launchers, then favorites, then the rest by name; this is the
  ## order search results keep among equally relevant matches.
  result = menu.launchersFor(menu.store.recent)
  for launcher in menu.launchersFor(menu.store.favorites):
    if launcher notin result:
      result.add launcher
  let front = result
  for launcher in menu.apps.all:
    if launcher notin front:
      result.add launcher

proc defaultButton(menu: MenuWindow): GtkWidget =
  case defaultCategory
  of dcFavorites: menu.pageButtons[pkFavorites]
  of dcRecent: menu.pageButtons[pkRecent]
  of dcAll: menu.pageButtons[pkApplications]

proc showDefaultPage(menu: MenuWindow) =
  gtk_toggle_button_set_active(menu.defaultButton, 1)
  gtk_entry_set_text(menu.searchEntry, "")
  let view = menu.views[menu.activePage]
  selectFirst(view)
  # Keep the first item selected (not just cursor)
  let model = gtk_icon_view_get_model(view)
  var iter: GtkTreeIter
  if model != nil and gtk_tree_model_get_iter_first(model, addr iter) != 0:
    let path = gtk_tree_model_get_path(model, addr iter)
    gtk_icon_view_select_path(view, path)
    gtk_tree_path_free(path)
  gtk_widget_grab_focus(menu.searchEntry)

proc onCategoryToggled(button: GtkWidget, data: pointer) {.cdecl.} =
  let menu = data.toMenu
  if gtk_toggle_button_get_active(button) != 0:
    let
      page = PageKind(cast[int](g_object_get_data(button, pageKey)))
      view = menu.views[page]
    if page == pkApplications:
      # Category 0 is "All Applications"; the rest follow `apps.categories`.
      let index = cast[int](g_object_get_data(button, categoryKey))
      if index == 0:
        view.setItems(menu.apps.all)
      elif index <= menu.apps.categories.len:
        view.setItems(menu.apps.categories[index - 1].items)
    resetSelection(view)
    gtk_stack_set_visible_child_name(menu.panelsStack, pageNames[page])
    gtk_widget_grab_focus(menu.searchEntry)

proc newCategoryButton(menu: MenuWindow, icon: GIcon, text: string,
    page: PageKind, category = 0): GtkWidget =
  result = gtk_radio_button_new(nil)
  gtk_toggle_button_set_mode(result, 0)
  gtk_button_set_relief(result, GTK_RELIEF_NONE)
  gtk_widget_set_tooltip_text(result, cstring(text))
  gtk_widget_set_focus_on_click(result, 0)
  let
    box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4)
    image = gtk_image_new_from_gicon(icon, GTK_ICON_SIZE_BUTTON)
  gtk_image_set_pixel_size(image, categoryIconSize)
  gtk_box_pack_start(box, image, 1, 1, 0)
  gtk_container_add(result, box)
  result.addClass("category-button")
  g_object_set_data(result, pageKey, cast[pointer](ord(page)))
  g_object_set_data(result, categoryKey, cast[pointer](category))
  g_signal_connect(result, "toggled", cast[GCallback](onCategoryToggled),
      cast[pointer](menu))
  gtk_widget_show_all(result)

proc newPageButton(menu: MenuWindow, iconName, text: string,
    page: PageKind): GtkWidget =
  let icon = newIcon(iconName)
  result = menu.newCategoryButton(icon, text, page)
  g_object_unref(icon)

proc reload(menu: MenuWindow) =
  ## Rereads the application menu and rebuilds everything derived from it.
  gtk_toggle_button_set_active(menu.defaultButton, 1)
  for view in menu.views:
    gtk_icon_view_set_model(view, nil)
  for button in menu.categoryWidgets:
    gtk_widget_destroy(button)
  menu.categoryWidgets.setLen(0)
  menu.closeActions() # Its actions hold launchers that are about to go.
  menu.clearSettings()
  menu.search.setLaunchers(@[])

  menu.apps.load()

  var last = menu.pageButtons[pkApplications]
  for i, category in menu.apps.categories:
    let button = menu.newCategoryButton(category.icon, category.name,
        pkApplications, i + 1)
    gtk_radio_button_join_group(button, last)
    gtk_box_pack_start(menu.categoryButtons, button, 0, 0, 0)
    menu.categoryWidgets.add button
    last = button
  menu.views[pkApplications].setItems(menu.apps.all)
  menu.refreshFavorites()
  menu.refreshRecent()

# --- Showing and hiding -----------------------------------------------------

proc isVisible*(menu: MenuWindow): bool =
  gtk_widget_get_visible(menu.window) != 0

proc hide*(menu: MenuWindow, lostFocus = false) =
  ## Closes the menu and resets it for the next time it opens.
  menu.closeActions()
  menu.store.save()
  # Hidden so no button keeps its hover border; `show` brings them back.
  for button in menu.commandButtons:
    gtk_widget_hide(button)
  gtk_widget_hide(menu.window)
  menu.showDefaultPage()
  if not lostFocus and menu.onClosed != nil:
    menu.onClosed(menu.hostData)

proc moveWindow(menu: MenuWindow) =
  menu.geometry.x = clamp(menu.geometry.x, menu.monitor.x,
      max(menu.monitor.x,
        menu.monitor.x + menu.monitor.width - menu.geometry.width))
  menu.geometry.y = clamp(menu.geometry.y, menu.monitor.y,
      max(menu.monitor.y,
        menu.monitor.y + menu.monitor.height - menu.geometry.height))
  if gtk_layer_is_supported() != 0:
    gtk_layer_set_margin(menu.window, GTK_LAYER_SHELL_EDGE_LEFT,
        menu.geometry.x - menu.monitor.x)
    gtk_layer_set_margin(menu.window, GTK_LAYER_SHELL_EDGE_TOP,
        menu.geometry.y - menu.monitor.y)
  else:
    gtk_window_move(menu.window, menu.geometry.x, menu.geometry.y)

proc place(menu: MenuWindow) =
  if menu.positionAt != nil:
    menu.positionAt(menu.hostData, menu.window, menu.geometry.x,
        menu.geometry.y)
  else:
    menu.geometry.x = menu.monitor.x +
        (menu.monitor.width - menu.geometry.width) div 2
    menu.geometry.y = menu.monitor.y +
        (menu.monitor.height - menu.geometry.height) div 2
  menu.moveWindow()

proc show*(menu: MenuWindow) =
  ## Opens the menu at the position given by `positionAt`.
  if menu.apps.stale:
    menu.reload()
  for button in menu.commandButtons:
    refreshCommandButton(button)
  menu.showDefaultPage()
  for page in pkFavorites .. pkApplications:
    if page != menu.activePage:
      resetSelection(menu.views[page])

  let display = gdk_display_get_default()
  var monitor = gdk_display_get_monitor(display, 0)
  if menu.attachWidget != nil and
      gtk_widget_get_window(menu.attachWidget) != nil:
    monitor = gdk_display_get_monitor_at_window(display,
        gtk_widget_get_window(menu.attachWidget))
  if gtk_layer_is_supported() != 0:
    gtk_layer_set_monitor(menu.window, monitor)
  gdk_monitor_get_geometry(monitor, addr menu.monitor)

  let
    width = clamp(cint(menuWidth), 10, menu.monitor.width)
    height = clamp(cint(menuHeight), 10, menu.monitor.height)
  if menu.geometry.width != width or menu.geometry.height != height:
    menu.geometry.width = width
    menu.geometry.height = height
    gtk_widget_set_size_request(menu.window, width, height)
    gtk_window_resize(menu.window, 1, 1)
  menu.place()
  gtk_window_present(menu.window)

  # The theme may make the window larger than requested; place it again
  # with its real size so it does not overlap the panel.
  var size: GtkRequisition
  gtk_widget_get_preferred_size(menu.window, addr size, nil)
  menu.geometry.width = max(size.width, menu.geometry.width)
  menu.geometry.height = max(size.height, menu.geometry.height)
  menu.place()

proc setSearchText*(menu: MenuWindow, text: string) =
  ## Types `text` into the search entry, as the user would.
  gtk_entry_set_text(menu.searchEntry, cstring(text))

# --- Launching and the context menu -----------------------------------------

proc remember(menu: MenuWindow, launcher: Element, fromPage: PageKind) =
  if fromPage != pkFavorites or favoritesInRecent or
      not menu.store.isFavorite(launcher.desktopId):
    menu.store.addRecent(launcher.desktopId)
    menu.refreshRecent()

proc pageOf(menu: MenuWindow, view: GtkWidget): PageKind =
  result = pkSearch
  for page, candidate in menu.views:
    if candidate == view:
      result = page

proc onItemActivated(view: GtkWidget, path: GtkTreePath, data: pointer)
    {.cdecl.} =
  let
    menu = data.toMenu
    element = elementAt(view, path)
  if element != nil:
    let screen = gtk_widget_get_screen(view)
    if element.kind == ekLauncher:
      menu.remember(element, menu.pageOf(view))
    menu.hide()
    element.run(screen)

proc showError(error: ptr GError, message: cstring) =
  xfce_dialog_show_error(nil, error, "%s", message)
  if error != nil:
    g_error_free(error)

proc addToDesktop(launcher: Element) =
  let
    folder = g_file_new_for_path(g_get_user_special_dir(
        G_USER_DIRECTORY_DESKTOP))
    source = garcon_menu_item_get_file(launcher.item)
    basename = g_file_get_basename(source)
    destination = g_file_get_child(folder, basename)
  var error: ptr GError
  if g_file_copy(source, destination, G_FILE_COPY_NONE, nil, nil, nil,
      addr error) != 0:
    let path = g_file_get_path(destination)
    discard g_chmod(path, 0o755)
    g_free(path)
    discard xfce_g_file_set_trusted(destination, 1, nil, nil)
  else:
    showError(error, "Unable to add launcher to desktop.")
  g_free(basename)
  g_object_unref(destination)
  g_object_unref(source)
  g_object_unref(folder)

proc addToPanel(launcher: Element) =
  var error: ptr GError
  let proxy = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION, 0, nil,
      "org.xfce.Panel", "/org/xfce/Panel", "org.xfce.Panel", nil, addr error)
  if proxy == nil:
    showError(error, "Unable to add launcher to panel.")
  else:
    var parameters = [cstring(launcher.desktopId), nil]
    let reply = g_dbus_proxy_call_sync(proxy, "AddNewItem",
        g_variant_new("(s^as)", cstring"launcher", addr parameters[0]), 0, -1,
        nil, addr error)
    if reply == nil:
      showError(error, "Unable to add launcher to panel.")
    else:
      g_variant_unref(reply)
    g_object_unref(proxy)

proc edit(launcher: Element) =
  var error: ptr GError
  let command = "exo-desktop-item-edit '" & launcher.uri & "'"
  if g_spawn_command_line_async(cstring(command), addr error) == 0:
    showError(error, "Unable to edit launcher.")

proc showItemActions(menu: MenuWindow, view: GtkWidget, path: GtkTreePath)
  ## Opens the actions panel for the application at `path`.

proc onViewButtonPress(view: GtkWidget, event: GdkEvent, data: pointer):
    gboolean {.cdecl.} =
  let menu = data.toMenu
  var x, y: cdouble
  discard gdk_event_get_coords(event, addr x, addr y)
  let path = gtk_icon_view_get_path_at_pos(view, cint(x), cint(y))
  if path != nil:
    if gdk_event_triggers_context_menu(event) != 0:
      menu.showItemActions(view, path)
      result = 1
    gtk_tree_path_free(path)

proc onViewPopupMenu(view: GtkWidget, data: pointer): gboolean {.cdecl.} =
  ## Context menu from the keyboard (Menu key or Shift+F10).
  var path: GtkTreePath
  if gtk_icon_view_get_cursor(view, addr path, nil) != 0 and path != nil:
    data.toMenu.showItemActions(view, path)
    gtk_tree_path_free(path)
    result = 1

proc newView(menu: MenuWindow, page: PageKind): GtkWidget =
  ## Creates the icon view for `page`.
  let view = gtk_icon_view_new()
  view.addIconRenderer(launcherIconSize)
  gtk_icon_view_set_markup_column(view, textColumn)
  gtk_icon_view_set_tooltip_column(view,
      if launcherShowTooltip: tooltipColumn else: -1)
  gtk_icon_view_set_item_padding(view, launcherItemPadding)
  gtk_icon_view_set_activate_on_single_click(view, 1)
  gtk_icon_view_set_selection_mode(view,
      GTK_SELECTION_SINGLE)
  view.addClass("launchers")
  gtk_widget_add_events(view, GDK_SCROLL_MASK)
  let self = cast[pointer](menu)
  g_signal_connect(view, "leave-notify-event", cast[GCallback](onViewLeave),
      self)
  g_signal_connect(view, "motion-notify-event", cast[GCallback](onViewPointer),
      self)
  g_signal_connect(view, "scroll-event", cast[GCallback](onViewPointer), self)
  g_signal_connect(view, "item-activated", cast[GCallback](onItemActivated),
      self)
  g_signal_connect(view, "button-press-event",
      cast[GCallback](onViewButtonPress), self)
  g_signal_connect(view, "popup-menu", cast[GCallback](onViewPopupMenu), self)
  menu.views[page] = view
  result = view

proc newPane(child: GtkWidget): GtkWidget =
  ## Wraps `child` in the framed, vertically scrolling launcher pane.
  result = gtk_scrolled_window_new(nil, nil)
  gtk_scrolled_window_set_policy(result, GTK_POLICY_NEVER,
      GTK_POLICY_AUTOMATIC)
  gtk_scrolled_window_set_shadow_type(result, GTK_SHADOW_ETCHED_IN)
  gtk_container_add(result, child)
  result.addClass("launchers-pane")

proc addRow(list: GtkWidget, icon: GIcon, name, detail, tooltip: string):
    GtkWidget =
  ## Appends an "icon  name  dim detail" row to a results list and returns
  ## the row widget.
  let
    image = gtk_image_new_from_gicon(icon, GTK_ICON_SIZE_LARGE_TOOLBAR)
    label = gtk_label_new(nil)
    box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
    escapedName = takeString(g_markup_escape_text(cstring(name), -1))
    escapedDetail = takeString(g_markup_escape_text(cstring(detail), -1))
  gtk_image_set_pixel_size(image, 24)
  gtk_label_set_markup(label, cstring(escapedName &
      "  <span size=\"small\" alpha=\"60%\">" & escapedDetail & "</span>"))
  gtk_label_set_ellipsize(label, PANGO_ELLIPSIZE_MIDDLE)
  gtk_label_set_xalign(label, 0)
  gtk_box_pack_start(box, image, 0, 0, 0)
  gtk_box_pack_start(box, label, 1, 1, 0)
  gtk_container_set_border_width(box, 3)
  if tooltip.len > 0:
    gtk_widget_set_tooltip_text(box, cstring(tooltip))
  gtk_list_box_insert(list, box, -1)
  result = gtk_widget_get_parent(box)
  gtk_widget_show_all(result)

proc newSection(title: string, list: var GtkWidget): GtkWidget =
  ## A titled results list for the search page; hidden until it has rows.
  result = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
  let header = gtk_label_new(cstring(title))
  gtk_label_set_xalign(header, 0)
  header.addClass("dim-label")
  list = gtk_list_box_new()
  gtk_box_pack_start(result, header, 0, 0, 0)
  gtk_box_pack_start(result, list, 0, 0, 0)

# --- Actions panel ------------------------------------------------------------
# Tab (or a right click) swaps the results for a panel about one item: its
# icon and name on top, then what can be done with it. It lives inside the
# menu window, so there is no popup to take over input, and keyboard focus
# stays in the search entry like everywhere else.

proc iconString(icon: GIcon): string =
  ## A GIcon as text, to keep it in an `ActionPage` without owning it.
  if icon != nil:
    result = takeString(g_icon_to_string(icon))

proc iconFor(text: string): GIcon =
  ## The GIcon for an icon name or a serialized GIcon; never `nil`.
  if text.len > 0:
    result = g_icon_new_for_string(cstring(text), nil)
  if result == nil:
    result = g_themed_icon_new("application-x-executable")

proc entry(icon, label: string, run: proc () {.closure.}, enabled = true,
    opensPage = false): ActionEntry =
  ActionEntry(icon: icon, label: label, run: run, enabled: enabled,
      opensPage: opensPage)

proc selectedAction(menu: MenuWindow): int =
  let row = gtk_list_box_get_selected_row(menu.actionsList)
  if row != nil:
    result = int(gtk_list_box_row_get_index(row))
  else:
    result = -1

proc scrollToAction(menu: MenuWindow, row: GtkWidget) =
  ## Keeps the selected row in view when the list is longer than the panel.
  let adjustment = gtk_scrolled_window_get_vadjustment(menu.actionsScroll)
  var x, y: cint
  gtk_widget_translate_coordinates(row, menu.actionsList, 0, 0, addr x, addr y)
  let
    top = gtk_adjustment_get_value(adjustment)
    page = gtk_adjustment_get_page_size(adjustment)
    bottom = cdouble(y + gtk_widget_get_allocated_height(row))
  if cdouble(y) < top:
    gtk_adjustment_set_value(adjustment, cdouble(y))
  elif bottom > top + page:
    gtk_adjustment_set_value(adjustment, bottom - page)

proc selectAction(menu: MenuWindow, index: int) =
  gtk_list_box_select_row(menu.actionsList, menu.actionRows[index])
  menu.scrollToAction(menu.actionRows[index])

proc renderActions(menu: MenuWindow) =
  ## Fills the panel from the page on top of the stack.
  let page = menu.actionPages[^1]
  let icon = iconFor(page.icon)
  gtk_image_set_from_gicon(menu.actionsIcon, icon, GTK_ICON_SIZE_DIALOG)
  g_object_unref(icon)
  gtk_label_set_markup(menu.actionsTitle, cstring("<b>" &
      takeString(g_markup_escape_text(cstring(page.title), -1)) & "</b>"))
  gtk_label_set_markup(menu.actionsSubtitle, cstring("<span alpha=\"60%\">" &
      takeString(g_markup_escape_text(cstring(page.subtitle), -1)) & "</span>"))
  for row in menu.actionRows:
    gtk_widget_destroy(row)
  menu.actionRows.setLen(0)
  var first = -1
  if page.selected in 0 ..< page.entries.len and
      page.entries[page.selected].enabled:
    first = page.selected
  for i, action in page.entries:
    let rowIcon = iconFor(action.icon)
    let row = addRow(menu.actionsList, rowIcon, action.label,
        if action.opensPage: "\u203A" else: "", "")
    g_object_unref(rowIcon)
    if not action.enabled:
      gtk_widget_set_sensitive(row, 0)
    elif first < 0:
      first = i
    menu.actionRows.add row
  if first >= 0:
    menu.selectAction(first) # The first action is always ready.

proc showActions(menu: MenuWindow, page: ActionPage) =
  ## Opens the panel on `page`. A page opened from another one goes on top
  ## of it, and Esc comes back to the one below.
  if menu.actionPages.len == 0:
    menu.actionsReturn = $gtk_stack_get_visible_child_name(menu.contentsStack)
  else:
    menu.actionPages[^1].selected = menu.selectedAction # For Esc.
  menu.actionPages.add page
  menu.renderActions()
  gtk_stack_set_visible_child_name(menu.contentsStack, "actions")

proc closeActions(menu: MenuWindow) =
  if menu.actionPages.len > 0:
    menu.actionPages.setLen(0)
    gtk_stack_set_visible_child_name(menu.contentsStack,
        cstring(menu.actionsReturn))
    gtk_widget_grab_focus(menu.searchEntry)

proc backActions(menu: MenuWindow) =
  if menu.actionPages.len > 1:
    menu.actionPages.setLen(menu.actionPages.len - 1)
    menu.renderActions()
  else:
    menu.closeActions()

proc moveAction(menu: MenuWindow, step: int) =
  ## Moves to the next (or previous) enabled action, wrapping around.
  let entries = menu.actionPages[^1].entries
  var index = menu.selectedAction
  if index < 0 and step < 0:
    index = 0
  for _ in 0 ..< entries.len:
    index = (index + step + entries.len) mod entries.len
    if entries[index].enabled:
      menu.selectAction(index)
      return

proc runAction(menu: MenuWindow, index: int) =
  if menu.actionPages.len > 0:
    let entries = menu.actionPages[^1].entries # A copy: `run` may change pages.
    if index in 0 ..< entries.len and entries[index].enabled:
      entries[index].run()

proc handleActionKey(menu: MenuWindow, keyval: cuint) =
  ## Keys while the panel is open; it takes all of them.
  case keyval
  of GDK_KEY_Up, GDK_KEY_KP_Up:
    menu.moveAction(-1)
  of GDK_KEY_Down, GDK_KEY_KP_Down:
    menu.moveAction(1)
  of GDK_KEY_Return, GDK_KEY_KP_Enter:
    menu.runAction(menu.selectedAction)
  of GDK_KEY_Right, GDK_KEY_KP_Right:
    let index = menu.selectedAction # Right goes into a sub-list, nothing else.
    if index in 0 ..< menu.actionPages[^1].entries.len and
        menu.actionPages[^1].entries[index].opensPage:
      menu.runAction(index)
  of GDK_KEY_Escape, GDK_KEY_Left, GDK_KEY_KP_Left, GDK_KEY_BackSpace:
    menu.backActions()
  of GDK_KEY_Tab, GDK_KEY_ISO_Left_Tab:
    menu.closeActions()
  else:
    discard

proc onActionActivated(list, row: GtkWidget, data: pointer) {.cdecl.} =
  data.toMenu.runAction(int(gtk_list_box_row_get_index(row)))

# Closures made inside a loop would all share the loop's variables (and so
# all run the last item); each one is built in its own call instead.

proc desktopActionEntry(menu: MenuWindow, launcher: Element, page: PageKind,
    act: DesktopAction): ActionEntry =
  entry(act.icon, act.name, proc () =
    let screen = gtk_widget_get_screen(menu.window)
    menu.remember(launcher, page)
    menu.hide()
    launcher.runAction(screen, act))

proc launcherActions(menu: MenuWindow, launcher: Element, page: PageKind):
    ActionPage =
  ## What can be done with an application or settings dialog.
  result.icon = iconString(launcher.icon)
  result.title = launcher.displayName
  result.subtitle = launcher.tooltip
  for act in launcher.actions:
    result.entries.add menu.desktopActionEntry(launcher, page, act)
  if menu.store.isFavorite(launcher.desktopId):
    result.entries.add entry("list-remove", "Remove from Favorites", proc () =
      menu.store.removeFavorite(launcher.desktopId)
      menu.refreshFavorites()
      menu.closeActions())
  else:
    result.entries.add entry("bookmark-new", "Add to Favorites", proc () =
      menu.store.addFavorite(launcher.desktopId)
      menu.refreshFavorites()
      menu.closeActions()
      gtk_toggle_button_set_active(menu.pageButtons[pkFavorites], 1)
      gtk_entry_set_text(menu.searchEntry, ""))
  result.entries.add entry("list-add", "Add to Desktop", proc () =
    addToDesktop(launcher)
    menu.closeActions())
  result.entries.add entry("list-add", "Add to Panel", proc () =
    addToPanel(launcher)
    menu.closeActions())
  result.entries.add entry("gtk-edit", "Edit Application...", proc () =
    menu.hide()
    edit(launcher))
  if page == pkRecent:
    result.entries.add entry("edit-clear", "Clear Recently Used", proc () =
      menu.store.clearRecent()
      menu.refreshRecent()
      menu.closeActions())

proc showItemActions(menu: MenuWindow, view: GtkWidget, path: GtkTreePath) =
  let launcher = elementAt(view, path)
  if launcher != nil and launcher.kind == ekLauncher:
    let indices = gtk_tree_path_get_indices(path)
    if view == menu.searchView and indices != nil:
      menu.setCursor(secApps, int(indices[]))
    else:
      gtk_icon_view_select_path(view, path)
    menu.showActions(menu.launcherActions(launcher, menu.pageOf(view)))

proc clearSettings(menu: MenuWindow) =
  for row in menu.settingRows:
    gtk_widget_destroy(row)
  menu.settingRows.setLen(0)
  menu.settingItems.setLen(0)
  gtk_widget_hide(menu.settingsBox)

proc showSettings(menu: MenuWindow, settings: seq[Element]) =
  menu.clearSettings()
  for launcher in settings:
    menu.settingRows.add addRow(menu.settingsList, launcher.icon,
        launcher.displayName, launcher.tooltip, "")
  menu.settingItems = settings
  if settings.len > 0:
    gtk_widget_show(menu.settingsBox)

proc onSettingActivated(list, row: GtkWidget, data: pointer) {.cdecl.} =
  let
    menu = data.toMenu
    index = gtk_list_box_row_get_index(row)
  if index >= 0 and index < menu.settingItems.len:
    let
      launcher = menu.settingItems[index]
      screen = gtk_widget_get_screen(list)
    menu.remember(launcher, pkSearch)
    menu.hide()
    launcher.run(screen)

# --- File results -----------------------------------------------------------

proc homeDir(): string =
  getHomeDir().strip(leading = false, chars = {'/'})

proc clearFiles(menu: MenuWindow) =
  for row in menu.fileRows:
    gtk_widget_destroy(row)
  menu.fileRows.setLen(0)
  menu.filePaths.setLen(0)
  gtk_widget_hide(menu.filesBox)

proc fileIcon(path: string): GIcon =
  if dirExists(path):
    result = g_themed_icon_new("folder")
  else:
    let contentType = g_content_type_guess(cstring(path), nil, 0, nil)
    result = g_content_type_get_icon(contentType)
    g_free(contentType)

proc onFileResults(data: pointer, paths: seq[string]) =
  ## Fills the "Files" list under the application results.
  let menu = data.toMenu
  menu.clearFiles()
  for path in paths:
    let icon = fileIcon(path)
    menu.fileRows.add addRow(menu.filesList, icon,
        path[path.rfind('/') + 1 .. ^1], displayDir(path, homeDir()), path)
    g_object_unref(icon)
  menu.filePaths = paths
  if paths.len > 0:
    gtk_widget_show(menu.filesBox)
    gtk_widget_hide(menu.message) # "No applications found" would mislead.
  # Something is always selected: when the old rows (and the selection on
  # one of them) are replaced, or nothing else matched, take the first result.
  if menu.activePage == pkSearch and menu.cursor.index < 0:
    menu.selectFirstResult()

proc openPath(path: string) =
  ## Opens a file or folder with its default application.
  let
    file = g_file_new_for_path(cstring(path))
    uri = g_file_get_uri(file)
  var error: ptr GError
  if g_app_info_launch_default_for_uri(uri, nil, addr error) == 0:
    showError(error, "Unable to open file.")
  g_free(uri)
  g_object_unref(file)

proc showInFolder(path: string) =
  ## Asks the file manager to open the containing folder with the file
  ## selected; falls back to just opening the folder.
  let
    file = g_file_new_for_path(cstring(path))
    uri = g_file_get_uri(file)
    proxy = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION, 0, nil,
        "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
        "org.freedesktop.FileManager1", nil, nil)
  var shown = false
  if proxy != nil:
    var uris = [uri, nil]
    let reply = g_dbus_proxy_call_sync(proxy, "ShowItems",
        g_variant_new("(^ass)", addr uris[0], cstring""), 0, 3000, nil, nil)
    if reply != nil:
      shown = true
      g_variant_unref(reply)
    g_object_unref(proxy)
  if not shown:
    openPath(path[0 ..< max(path.rfind('/'), 1)])
  g_free(uri)
  g_object_unref(file)

proc onFileActivated(list, row: GtkWidget, data: pointer) {.cdecl.} =
  let
    menu = data.toMenu
    index = gtk_list_box_row_get_index(row)
  if index >= 0 and index < menu.filePaths.len:
    let path = menu.filePaths[index]
    menu.hide()
    openPath(path)

proc launchWith(app: GAppInfo, path: string) =
  let
    file = g_file_new_for_path(cstring(path))
    uri = g_file_get_uri(file)
    uris = g_list_append(nil, uri)
  var error: ptr GError
  if g_app_info_launch_uris(app, uris, nil, addr error) == 0:
    showError(error, "Unable to open file.")
  g_list_free(uris)
  g_free(uri)
  g_object_unref(file)

proc showProperties(path: string) =
  ## Asks the file manager for the file's properties dialog.
  let
    file = g_file_new_for_path(cstring(path))
    uri = g_file_get_uri(file)
    proxy = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION, 0, nil,
        "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
        "org.freedesktop.FileManager1", nil, nil)
  var shown = false
  if proxy != nil:
    var uris = [uri, nil]
    let reply = g_dbus_proxy_call_sync(proxy, "ShowItemProperties",
        g_variant_new("(^ass)", addr uris[0], cstring""), 0, 3000, nil, nil)
    if reply != nil:
      shown = true
      g_variant_unref(reply)
    g_object_unref(proxy)
  if not shown:
    showInFolder(path)
  g_free(uri)
  g_object_unref(file)

proc trashFile(path: string) =
  let file = g_file_new_for_path(cstring(path))
  var error: ptr GError
  if g_file_trash(file, nil, addr error) == 0:
    showError(error, "Unable to move the file to the trash.")
  g_object_unref(file)

proc copyToClipboard(text: string) =
  let clipboard = gtk_clipboard_get(gdk_atom_intern("CLIPBOARD", 0))
  gtk_clipboard_set_text(clipboard, cstring(text), -1)

type
  AppHolderObj = object
    app: GAppInfo
  AppHolder = ref AppHolderObj

proc `=destroy`(holder: AppHolderObj) =
  if holder.app != nil:
    g_object_unref(holder.app)

proc openWithEntry(menu: MenuWindow, holder: AppHolder, path: string):
    ActionEntry =
  entry(iconString(g_app_info_get_icon(holder.app)),
      $g_app_info_get_display_name(holder.app), proc () =
    menu.hide()
    launchWith(holder.app, path))

proc openWithPage(menu: MenuWindow, path: string, fileIcon: string):
    ActionPage =
  ## The applications that can open `path`.
  result.icon = fileIcon
  result.title = "Open With"
  result.subtitle = path[path.rfind('/') + 1 .. ^1]
  let
    contentType = g_content_type_guess(cstring(path), nil, 0, nil)
    apps = g_app_info_get_all_for_type(contentType)
  g_free(contentType)
  var node = apps
  while node != nil:
    let app = cast[GAppInfo](node.data) # The list's reference goes to `holder`.
    if g_app_info_should_show(app) != 0:
      result.entries.add menu.openWithEntry(AppHolder(app: app), path)
    else:
      g_object_unref(app)
    node = node.next
  g_list_free(apps)

proc fileActions(menu: MenuWindow, path: string): ActionPage =
  ## What can be done with a file: open it, open it with another
  ## application, show it in its folder, copy its path, trash it, show its
  ## properties.
  let icon = fileIcon(path)
  result.icon = iconString(icon)
  g_object_unref(icon)
  result.title = path[path.rfind('/') + 1 .. ^1]
  result.subtitle = displayDir(path, homeDir())
  let withPage = menu.openWithPage(path, result.icon)
  result.entries.add entry("document-open", "Open", proc () =
    menu.hide()
    openPath(path))
  result.entries.add entry("system-run", "Open With", proc () =
    menu.showActions(withPage),
      enabled = withPage.entries.len > 0, opensPage = true)
  result.entries.add entry("folder-open", "Open Containing Folder", proc () =
    menu.hide()
    showInFolder(path))
  result.entries.add entry("edit-copy", "Copy Path", proc () =
    menu.hide()
    copyToClipboard(path))
  result.entries.add entry("user-trash", "Move to Trash", proc () =
    menu.hide()
    trashFile(path))
  result.entries.add entry("document-properties", "Properties", proc () =
    menu.hide()
    showProperties(path))

proc onListButtonPress(list: GtkWidget, event: GdkEvent, data: pointer):
    gboolean {.cdecl.} =
  ## Right-click on a Settings or Files row opens that item's actions.
  let menu = data.toMenu
  var x, y: cdouble
  discard gdk_event_get_coords(event, addr x, addr y)
  let row = gtk_list_box_get_row_at_y(list, cint(y))
  if row != nil and gdk_event_triggers_context_menu(event) != 0:
    let index = int(gtk_list_box_row_get_index(row))
    if list == menu.filesList and index in 0 ..< menu.filePaths.len:
      menu.setCursor(secFiles, index)
      menu.showActions(menu.fileActions(menu.filePaths[index]))
      result = 1
    elif list == menu.settingsList and index in 0 ..< menu.settingItems.len:
      menu.setCursor(secSettings, index)
      menu.showActions(menu.launcherActions(menu.settingItems[index],
          pkSearch))
      result = 1

# --- Search -----------------------------------------------------------------

proc setFilter(menu: MenuWindow, text: string) =
  gtk_widget_hide(menu.message)
  if text.len == 0:
    menu.search.clear()
    menu.clearSettings()
  elif text != menu.search.text:
    if menu.search.text.len == 0:
      menu.search.setLaunchers(menu.searchOrder())
    var noResults: bool
    let results = menu.search.update(text, noResults)
    if noResults:
      gtk_widget_show(menu.message)
    # Settings dialogs get their own list under the applications.
    var apps, settings: seq[Element]
    for element in results:
      if element.kind == ekLauncher and element.isSetting:
        if settings.len < searchMaxSettings:
          settings.add element
      elif searchMaxApps == 0 or apps.len < searchMaxApps:
        apps.add element
    menu.views[pkSearch].setItems(apps)
    # With no application match the lists move up to the top.
    gtk_widget_set_visible(menu.searchPane, gboolean(apps.len > 0))
    menu.showSettings(settings)
    # A new query always starts on its first result.
    menu.gridColumn = 0
    menu.selectFirstResult()

proc onSearchChanged(entry: GtkWidget, data: pointer) {.cdecl.} =
  let
    menu = data.toMenu
    text = $gtk_entry_get_text(entry)
  gtk_stack_set_visible_child_name(menu.contentsStack,
      if text.len > 0: cstring"search" else: cstring"contents")
  menu.resultsMode = false # Typing goes back to editing the query.
  menu.closeActions()
  menu.setFilter(text)
  if fileSearchEnabled and isFileQuery(text, fileSearchMinChars):
    # Earlier file results stay up until the new ones arrive.
    menu.files.request(text.strip())
  else:
    menu.files.cancel()
    menu.clearFiles()

proc showOptions(menu: MenuWindow) =
  ## Tab: opens the actions panel for the selected item (an application's
  ## actions and favorites; a file's Open, Open With, Open Containing
  ## Folder, ...).
  if menu.activePage == pkSearch:
    let (section, index) = menu.cursor
    if index >= 0:
      case section
      of secApps:
        let path = gtk_tree_path_new_from_indices(cint(index), cint(-1))
        menu.showItemActions(menu.searchView, path)
        gtk_tree_path_free(path)
      of secSettings:
        menu.showActions(menu.launcherActions(menu.settingItems[index],
            pkSearch))
      of secFiles:
        menu.showActions(menu.fileActions(menu.filePaths[index]))
  else:
    let
      view = menu.views[menu.activePage]
      selection = gtk_icon_view_get_selected_items(view)
    if selection != nil:
      menu.showItemActions(view, cast[GtkTreePath](selection.data))
      freePaths(selection)

proc onSearchActivate(entry: GtkWidget, data: pointer) {.cdecl.} =
  ## Enter opens the selected item.
  let menu = data.toMenu
  menu.setFilter($gtk_entry_get_text(entry))
  if menu.activePage == pkSearch:
    let (section, index) = menu.cursor
    if index >= 0:
      case section
      of secApps:
        let path = gtk_tree_path_new_from_indices(cint(index), cint(-1))
        gtk_icon_view_item_activated(menu.searchView, path)
        gtk_tree_path_free(path)
      of secSettings:
        onSettingActivated(menu.settingsList, menu.settingRows[index], data)
      of secFiles:
        onFileActivated(menu.filesList, menu.fileRows[index], data)
  else:
    let
      view = menu.views[menu.activePage]
      selection = gtk_icon_view_get_selected_items(view)
    if selection != nil:
      gtk_icon_view_item_activated(view, cast[GtkTreePath](selection.data))
      freePaths(selection)

proc onSearchStop(entry: GtkWidget, data: pointer) {.cdecl.} =
  if gtk_entry_get_text_length(entry) > 0:
    gtk_entry_set_text(entry, "")

proc onPopulatePopup(entry, popup: GtkWidget, data: pointer) {.cdecl.} =
  data.toMenu.childHasFocus = true

# --- Window events ----------------------------------------------------------

proc onRegainFocus(window: GtkWidget, event: GdkEvent, data: pointer):
    gboolean {.cdecl.} =
  data.toMenu.childHasFocus = false

proc hideOnIdle(data: pointer): gboolean {.cdecl.} =
  let menu = data.toMenu
  if menu.isVisible:
    menu.hide(lostFocus = true)

proc onFocusOut(window: GtkWidget, event: GdkEvent, data: pointer): gboolean
    {.cdecl.} =
  let menu = data.toMenu
  if not menu.stayOnFocusOut and not menu.childHasFocus and menu.isVisible:
    # Deferred so a click on the panel button is seen before the menu
    # hides; otherwise the button could never toggle it closed.
    discard g_idle_add(hideOnIdle, data)

proc onKeyPress(window: GtkWidget, event: GdkEvent, data: pointer): gboolean
    {.cdecl.} =
  ## Keys for the whole menu window. On the search page the keyboard focus
  ## stays in the entry and these keys move the selection through the
  ## results (application grid, Settings, Files); Tab opens the options of
  ## the selected item instead of moving focus.
  let
    menu = data.toMenu
    page = menu.activePage
    view = menu.views[page]
    entry = menu.searchEntry
    inSearch = gtk_window_get_focus(window) == entry
  var keyval: cuint
  discard gdk_event_get_keyval(event, addr keyval)
  if menu.actionPages.len > 0:
    menu.handleActionKey(keyval) # The actions panel takes every key.
    return 1
  case keyval
  of GDK_KEY_Escape:
    # Escape clears the search text first, then closes the menu.
    if gtk_entry_get_text_length(entry) == 0:
      menu.hide()
    else:
      gtk_entry_set_text(entry, "")
    result = 1
  of GDK_KEY_Tab, GDK_KEY_ISO_Left_Tab:
    menu.showOptions()
    result = 1
  of GDK_KEY_Left, GDK_KEY_KP_Left, GDK_KEY_Right, GDK_KEY_KP_Right:
    let
      rtl = gtk_widget_get_default_direction() == GTK_TEXT_DIR_RTL
      forward = if rtl: keyval in [GDK_KEY_Left, GDK_KEY_KP_Left]
                else: keyval in [GDK_KEY_Right, GDK_KEY_KP_Right]
      length = cint(gtk_entry_get_text_length(entry))
      atEnd = length > 0 and gtk_editable_get_position(entry) == length
    if page == pkSearch:
      # Left/Right edit the text, until Right at its end (or an Up/Down)
      # starts moving through the results; typing brings the text back.
      if menu.resultsMode or (forward and atEnd):
        menu.resultsMode = true
        discard menu.moveCursor(if keyval in [GDK_KEY_Right, GDK_KEY_KP_Right]:
          mvRight else: mvLeft)
        result = 1
    elif inSearch and forward and atEnd:
      gtk_widget_grab_focus(view)
  of GDK_KEY_Up, GDK_KEY_KP_Up, GDK_KEY_Down, GDK_KEY_KP_Down:
    let down = keyval in [GDK_KEY_Down, GDK_KEY_KP_Down]
    if page == pkSearch:
      menu.resultsMode = true
      if not menu.moveCursor(if down: mvDown else: mvUp) and not down:
        menu.resultsMode = false # Up from the first result: back to the text.
      result = 1
    else:
      let nothingSelected = not hasSelection(view)
      if inSearch and down:
        gtk_widget_grab_focus(view)
        selectFirst(view)
        result = 1
      elif gtk_window_get_focus(window) == view and nothingSelected:
        selectFirst(view)
        result = 1
  of GDK_KEY_Page_Up, GDK_KEY_KP_Page_Up, GDK_KEY_Page_Down,
      GDK_KEY_KP_Page_Down:
    if inSearch and page != pkSearch:
      gtk_widget_grab_focus(view)
  else:
    discard

proc onKeyPressAfter(window: GtkWidget, event: GdkEvent, data: pointer):
    gboolean {.cdecl.} =
  ## Typing anywhere in the menu goes to the search entry.
  let entry = data.toMenu.searchEntry
  if gtk_window_get_focus(window) != entry and not event.isModifier:
    gtk_entry_grab_focus_without_selecting(entry)
    discard gtk_window_propagate_key_event(window, event)
    result = 1

proc onMap(window: GtkWidget, event: GdkEvent, data: pointer): gboolean
    {.cdecl.} =
  gtk_window_set_keep_above(window, 1)

proc onDraw(window: GtkWidget, cr: Cairo, data: pointer): gboolean {.cdecl.} =
  ## Paints the themed window background, translucent when composited.
  let
    menu = data.toMenu
    context = gtk_widget_get_style_context(window)
    width = gtk_widget_get_allocated_width(window)
    height = gtk_widget_get_allocated_height(window)
  if menu.supportsAlpha and
      gdk_screen_is_composited(gtk_widget_get_screen(window)) != 0:
    let
      background = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width,
          height)
      backgroundCr = cairo_create(background)
    cairo_set_operator(backgroundCr, CAIRO_OPERATOR_SOURCE)
    gtk_render_background(context, backgroundCr, 0, 0, cdouble(width),
        cdouble(height))
    cairo_destroy(backgroundCr)
    cairo_set_source_surface(cr, background, 0, 0)
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    cairo_paint_with_alpha(cr, menuOpacity / 100)
    cairo_surface_destroy(background)
  else:
    gtk_render_background(context, cr, 0, 0, cdouble(width), cdouble(height))

proc onCommandClicked(button: GtkWidget, data: pointer) {.cdecl.} =
  data.toMenu.hide()

# --- Construction -----------------------------------------------------------

proc initWindow(menu: MenuWindow) =
  let
    window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
    self = cast[pointer](menu)
  menu.window = window
  gtk_widget_set_name(window, "whiskermenu-window")
  # Untranslated title so window managers can identify the menu.
  gtk_window_set_title(window, "Whisker Menu")
  gtk_window_set_decorated(window, 0)
  gtk_window_set_skip_taskbar_hint(window, 1)
  gtk_window_set_skip_pager_hint(window, 1)
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_MENU)
  gtk_window_stick(window)
  gtk_widget_add_events(window, GDK_FOCUS_CHANGE_MASK or GDK_STRUCTURE_MASK)
  if gtk_layer_is_supported() != 0:
    # Wayland: a layer surface positioned by margins from the top left.
    gtk_layer_init_for_window(window)
    gtk_layer_set_namespace(window, "whiskermenu")
    gtk_layer_set_exclusive_zone(window, -1)
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, 1)
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, 1)
    gtk_layer_set_keyboard_mode(window,
        GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND)
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY)
  else:
    gtk_window_set_modal(window, 1)

  g_signal_connect(window, "enter-notify-event",
      cast[GCallback](onRegainFocus), self)
  g_signal_connect(window, "focus-in-event", cast[GCallback](onRegainFocus),
      self)
  g_signal_connect(window, "focus-out-event", cast[GCallback](onFocusOut),
      self)
  g_signal_connect(window, "key-press-event", cast[GCallback](onKeyPress),
      self)
  g_signal_connect_after(window, "key-press-event",
      cast[GCallback](onKeyPressAfter), self)
  g_signal_connect(window, "map-event", cast[GCallback](onMap), self)
  g_signal_connect(window, "delete-event",
      cast[GCallback](gtk_widget_hide_on_delete))
  g_signal_connect(window, "draw", cast[GCallback](onDraw), self)
  window.addClass("whiskermenu")

  # Translucency needs an RGBA visual, chosen before the window is realized.
  let
    screen = gtk_widget_get_screen(window)
    rgba = gdk_screen_get_rgba_visual(screen)
  menu.supportsAlpha = rgba != nil and menuOpacity < 100
  gtk_widget_set_visual(window,
      if menu.supportsAlpha: rgba else: gdk_screen_get_system_visual(screen))
  gtk_widget_set_app_paintable(window, 1)

proc buildContents(menu: MenuWindow): GtkWidget =
  ## Builds everything inside the window frame and returns the outer box.
  let self = cast[pointer](menu)
  result = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6)
  # Upstream surrounds the contents with 6 px resize handles.
  gtk_container_set_border_width(result, 6)

  # Upstream's header row. Empty in this layout (no profile, commands moved
  # beside the search entry) but still present, so it is kept for spacing.
  let titleBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)
  titleBox.addClass("title-area")
  gtk_box_pack_start(result, titleBox, 0, 0, 0)

  let
    searchBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)
    commandsBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)
  searchBox.addClass("search-area")
  commandsBox.addClass("commands-area")
  menu.searchEntry = gtk_search_entry_new()
  g_signal_connect(menu.searchEntry, "changed",
      cast[GCallback](onSearchChanged), self)
  g_signal_connect(menu.searchEntry, "activate",
      cast[GCallback](onSearchActivate), self)
  g_signal_connect(menu.searchEntry, "stop-search",
      cast[GCallback](onSearchStop), self)
  g_signal_connect(menu.searchEntry, "populate-popup",
      cast[GCallback](onPopulatePopup), self)
  gtk_box_pack_start(searchBox, menu.searchEntry, 1, 1, 0)
  gtk_box_pack_start(commandsBox, gtk_label_new(nil), 1, 1, 0)
  for i in 0 ..< sessionCommands.len:
    let button = newCommandButton(i)
    g_signal_connect(button, "clicked", cast[GCallback](onCommandClicked),
        self)
    gtk_box_pack_start(commandsBox, button, 0, 0, 0)
    menu.commandButtons.add button
  gtk_box_pack_start(searchBox, commandsBox, 0, 0, 0)
  gtk_box_pack_start(result, searchBox, 0, 1, 0)

  # Page buttons, default page first, then a separator and the categories.
  menu.pageButtons[pkFavorites] = menu.newPageButton("user-bookmarks",
      "Favorites", pkFavorites)
  menu.pageButtons[pkRecent] = menu.newPageButton("document-open-recent",
      "Recently Used", pkRecent)
  menu.pageButtons[pkApplications] = menu.newPageButton("applications-other",
      "All Applications", pkApplications)
  gtk_radio_button_join_group(menu.pageButtons[pkRecent],
      menu.pageButtons[pkFavorites])
  gtk_radio_button_join_group(menu.pageButtons[pkApplications],
      menu.pageButtons[pkRecent])
  menu.categoryButtons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)
  menu.categoryButtons.addClass("categories")
  menu.categoryButtons.addClass("top")
  const pageOrder: array[DefaultCategory, array[3, PageKind]] = [
    [pkFavorites, pkRecent, pkApplications],
    [pkRecent, pkFavorites, pkApplications],
    [pkApplications, pkFavorites, pkRecent]]
  for page in pageOrder[defaultCategory]:
    gtk_box_pack_start(menu.categoryButtons, menu.pageButtons[page], 0, 0, 0)
  gtk_box_pack_start(menu.categoryButtons,
      gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), 0, 0, 4)
  let categoriesBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)
  gtk_box_set_center_widget(categoriesBox, menu.categoryButtons)

  menu.panelsStack = gtk_stack_new()
  gtk_widget_set_hexpand(menu.panelsStack, 1)
  gtk_widget_set_vexpand(menu.panelsStack, 1)
  for page in pkFavorites .. pkApplications:
    gtk_stack_add_named(menu.panelsStack, newPane(menu.newView(page)),
        pageNames[page])

  let contentsBox = gtk_grid_new()
  gtk_grid_set_row_spacing(contentsBox, 6)
  gtk_grid_attach(contentsBox, categoriesBox, 0, 0, 1, 1)
  gtk_grid_attach(contentsBox, menu.panelsStack, 0, 1, 1, 1)

  # Search results replace the categories and pages while a query is typed.
  menu.message = gtk_info_bar_new()
  gtk_info_bar_set_message_type(menu.message, GTK_MESSAGE_INFO)
  gtk_container_add(gtk_info_bar_get_content_area(menu.message),
      gtk_label_new("No applications found"))
  let searchResults = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
  gtk_box_pack_start(searchResults, menu.message, 0, 0, 0)

  # Application grid on top with its own scrolling, then the settings and
  # files lists at their natural height. (One scrolling page for all three
  # was tried; GtkIconView does not lay out reliably inside a viewport.)
  menu.searchPane = newPane(menu.newView(pkSearch))
  gtk_widget_set_size_request(menu.searchPane, -1, searchGridMinHeight)
  gtk_box_pack_start(searchResults, menu.searchPane, 1, 1, 0)
  menu.settingsBox = newSection("Settings", menu.settingsList)
  menu.settingsList.addClass("settings-results")
  g_signal_connect(menu.settingsList, "row-activated",
      cast[GCallback](onSettingActivated), self)
  g_signal_connect(menu.settingsList, "button-press-event",
      cast[GCallback](onListButtonPress), self)
  gtk_box_pack_start(searchResults, menu.settingsBox, 0, 0, 0)
  menu.filesBox = newSection("Files", menu.filesList)
  menu.filesList.addClass("file-results")
  g_signal_connect(menu.filesList, "row-activated",
      cast[GCallback](onFileActivated), self)
  g_signal_connect(menu.filesList, "button-press-event",
      cast[GCallback](onListButtonPress), self)
  gtk_box_pack_start(searchResults, menu.filesBox, 0, 0, 0)

  # The actions panel: the item's icon and name, then its actions.
  menu.actionsBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)
  menu.actionsBox.addClass("actions-panel")
  gtk_container_set_border_width(menu.actionsBox, 8)
  let
    header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)
    titles = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
  menu.actionsIcon = gtk_image_new()
  gtk_image_set_pixel_size(menu.actionsIcon, 48)
  menu.actionsTitle = gtk_label_new(nil)
  menu.actionsSubtitle = gtk_label_new(nil)
  for label in [menu.actionsTitle, menu.actionsSubtitle]:
    gtk_label_set_xalign(label, 0)
    gtk_label_set_ellipsize(label, PANGO_ELLIPSIZE_MIDDLE)
  gtk_box_pack_start(titles, menu.actionsTitle, 0, 0, 0)
  gtk_box_pack_start(titles, menu.actionsSubtitle, 0, 0, 0)
  gtk_widget_set_valign(titles, GTK_ALIGN_CENTER)
  gtk_box_pack_start(header, menu.actionsIcon, 0, 0, 0)
  gtk_box_pack_start(header, titles, 1, 1, 0)
  menu.actionsList = gtk_list_box_new()
  g_signal_connect(menu.actionsList, "row-activated",
      cast[GCallback](onActionActivated), self)
  menu.actionsScroll = newPane(menu.actionsList)
  let hint = gtk_label_new(nil)
  gtk_label_set_markup(hint, "<span alpha=\"60%\" size=\"small\">" &
      "\u2191\u2193 choose     \u21B5 run     \u2192 more     " &
      "Esc back     Tab close</span>")
  gtk_box_pack_start(menu.actionsBox, header, 0, 0, 0)
  gtk_box_pack_start(menu.actionsBox, menu.actionsScroll, 1, 1, 0)
  gtk_box_pack_start(menu.actionsBox, hint, 0, 0, 0)

  menu.contentsStack = gtk_stack_new()
  menu.contentsStack.addClass("contents")
  gtk_stack_add_named(menu.contentsStack, contentsBox, "contents")
  gtk_stack_add_named(menu.contentsStack, searchResults, "search")
  gtk_stack_add_named(menu.contentsStack, menu.actionsBox, "actions")
  gtk_box_pack_start(result, menu.contentsStack, 1, 1, 0)

proc newMenuWindow*(store: Store): MenuWindow =
  ## Creates the hidden menu window and loads the application list. The
  ## window keeps a pointer to the returned object for its callbacks, so the
  ## object is kept alive for the life of the process.
  result = MenuWindow(store: store, apps: newAppList(), search: newSearch(),
      files: newFileSearch(), stayOnFocusOut: stayOnFocusOut)
  GC_ref(result)
  result.files.onResults = onFileResults
  result.files.data = cast[pointer](result)
  result.initWindow()
  let frame = gtk_frame_new(nil)
  gtk_frame_set_shadow_type(frame, GTK_SHADOW_OUT)
  gtk_container_add(result.window, frame)
  gtk_container_add(frame, result.buildContents())
  gtk_widget_show_all(frame)
  gtk_widget_hide(result.message)
  gtk_widget_hide(result.filesBox)
  gtk_widget_hide(result.settingsBox)
  result.reload()
  gtk_toggle_button_set_active(result.defaultButton, 1)
