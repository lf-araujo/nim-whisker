## xfce4-panel plugin entry point: the panel button that opens the menu.
## Ported from upstream `plugin.cpp` and `register-plugin.c`.
##
## Build with `--app:lib`. The panel loads the library and calls
## `xfce_panel_module_construct`, which is what upstream's
## `XFCE_PANEL_PLUGIN_REGISTER` macro expands to.

import whisker/[config, glib, gtk, menuwindow, store, xfcepanel]

type
  Plugin = ref object
    panelPlugin: XfcePanelPlugin
    button, box, icon, label: GtkWidget
    menu: MenuWindow
    hideTime: int64 ## Monotonic time the menu last hid by itself, or 0.
    autohideBlocked: bool

const constructedKey = "whisker-nim-constructed"

proc toPlugin(data: pointer): Plugin = cast[Plugin](data)

proc positionMenu(data: pointer, window: GtkWidget, x, y: var cint) =
  let self = data.toPlugin
  xfce_panel_plugin_position_widget(self.panelPlugin, window, self.button,
      addr x, addr y)

proc onMenuClosed(data: pointer) =
  data.toPlugin.hideTime = 0

proc onMenuHide(window: GtkWidget, data: pointer) {.cdecl.} =
  let self = data.toPlugin
  self.hideTime = g_get_monotonic_time()
  gtk_toggle_button_set_active(self.button, 0)
  if self.autohideBlocked:
    xfce_panel_plugin_block_autohide(self.panelPlugin, 0)
  self.autohideBlocked = false

proc showMenu(self: Plugin) =
  self.autohideBlocked = true
  xfce_panel_plugin_block_autohide(self.panelPlugin, 1)
  gtk_toggle_button_set_active(self.button, 1)
  self.menu.show()
  self.hideTime = 0

proc onButtonPress(button: GtkWidget, event: GdkEvent, data: pointer):
    gboolean {.cdecl.} =
  let self = data.toPlugin
  var pressed: cuint
  discard gdk_event_get_button(event, addr pressed)
  if gdk_event_get_event_type(event) == GDK_BUTTON_PRESS and pressed == 1:
    if gtk_toggle_button_get_active(button) == 0:
      self.showMenu()
    else:
      self.menu.hide()
    result = 1

proc onRemoteEvent(panelPlugin: XfcePanelPlugin, name: cstring,
    value, data: pointer): gboolean {.cdecl.} =
  ## Handles `xfce4-panel --plugin-event=whisker-nim:popup:bool:false`,
  ## for binding the menu to a keyboard shortcut.
  let self = data.toPlugin
  if $name == "popup":
    result = 1
    # A shortcut pressed while the menu is open first makes it lose focus
    # and hide; ignore the event that follows so the shortcut toggles.
    let sinceHide = g_get_monotonic_time() - self.hideTime
    let justHidden = self.hideTime != 0 and sinceHide < 250_000
    self.hideTime = 0
    if not justHidden:
      if self.menu.isVisible:
        self.menu.hide()
      else:
        self.showMenu()

proc onSizeChanged(panelPlugin: XfcePanelPlugin, size: cint, data: pointer):
    gboolean {.cdecl.} =
  let
    self = data.toPlugin
    panelOrientation = xfce_panel_plugin_get_orientation(panelPlugin)
    mode = xfce_panel_plugin_get_mode(panelPlugin)
    rows = cint(xfce_panel_plugin_get_nrows(panelPlugin))
  var
    orientation = panelOrientation
    iconSize = xfce_panel_plugin_get_icon_size(panelPlugin)
    buttonSize = size
  # The icon fills the button unless the title sits beside it.
  gtk_box_set_child_packing(self.box, self.icon,
      gboolean(not buttonTitleVisible), gboolean(not buttonTitleVisible), 0,
      GTK_PACK_START)
  if buttonSingleRow:
    buttonSize = size div rows
  else:
    iconSize *= rows
  gtk_image_set_pixel_size(self.icon, iconSize)

  if not buttonTitleVisible and (buttonSingleRow or rows == 1):
    gtk_widget_set_size_request(self.button, buttonSize, buttonSize)
  else:
    gtk_widget_set_size_request(self.button, -1, -1)

  if buttonTitleVisible or not buttonSingleRow:
    xfce_panel_plugin_set_small(panelPlugin, 0)
    # In deskbar mode the title goes beside the icon if it fits.
    var labelSize: GtkRequisition
    gtk_widget_get_preferred_size(self.label, nil, addr labelSize)
    if mode == XFCE_PANEL_PLUGIN_MODE_DESKBAR and buttonTitleVisible and
        buttonIconVisible and labelSize.width <= buttonSize - iconSize - 4:
      orientation = GTK_ORIENTATION_HORIZONTAL
  else:
    xfce_panel_plugin_set_small(panelPlugin, 1)

  let deskbarRow = panelOrientation == GTK_ORIENTATION_VERTICAL and
      orientation == GTK_ORIENTATION_HORIZONTAL
  gtk_box_set_child_packing(self.box, self.label, gboolean(not deskbarRow),
      gboolean(not deskbarRow), 0, GTK_PACK_START)
  gtk_orientable_set_orientation(self.box, orientation)
  result = 1

proc onModeChanged(panelPlugin: XfcePanelPlugin, mode: cint, data: pointer)
    {.cdecl.} =
  let self = data.toPlugin
  gtk_label_set_angle(self.label,
      if mode == XFCE_PANEL_PLUGIN_MODE_VERTICAL: 270 else: 0)
  discard onSizeChanged(panelPlugin, xfce_panel_plugin_get_size(panelPlugin),
      data)

proc onFreeData(panelPlugin: XfcePanelPlugin, data: pointer) {.cdecl.} =
  let self = data.toPlugin
  if self.menu.isVisible:
    self.menu.hide()
  gtk_widget_destroy(self.menu.window)

proc construct(panelPlugin: XfcePanelPlugin) =
  let
    self = Plugin(panelPlugin: panelPlugin)
    data = cast[pointer](self)
  GC_ref(self) # Referenced from C callbacks for the life of the panel.

  self.button = xfce_panel_create_toggle_button()
  gtk_widget_set_name(self.button, "whiskermenu-button")
  g_signal_connect(self.button, "button-press-event",
      cast[GCallback](onButtonPress), data)
  gtk_widget_show(self.button)

  self.box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2)
  gtk_container_add(self.button, self.box)
  gtk_widget_show(self.box)

  self.icon = gtk_image_new()
  gtk_image_set_from_icon_name(self.icon, buttonIcon, GTK_ICON_SIZE_BUTTON)
  gtk_box_pack_start(self.box, self.icon, 1, 0, 0)
  gtk_widget_set_visible(self.icon, gboolean(buttonIconVisible))

  self.label = gtk_label_new(nil)
  gtk_label_set_markup(self.label, buttonTitle)
  gtk_box_pack_start(self.box, self.label, 1, 1, 0)
  gtk_widget_set_visible(self.label, gboolean(buttonTitleVisible))
  gtk_widget_set_tooltip_markup(self.button, buttonTitle)
  gtk_widget_set_has_tooltip(self.button, gboolean(not buttonTitleVisible))

  gtk_container_add(cast[GtkWidget](panelPlugin), self.button)
  xfce_panel_plugin_add_action_widget(panelPlugin, self.button)
  g_signal_connect(panelPlugin, "free-data", cast[GCallback](onFreeData),
      data)
  g_signal_connect(panelPlugin, "mode-changed",
      cast[GCallback](onModeChanged), data)
  g_signal_connect(panelPlugin, "remote-event",
      cast[GCallback](onRemoteEvent), data)
  g_signal_connect(panelPlugin, "size-changed",
      cast[GCallback](onSizeChanged), data)
  onModeChanged(panelPlugin, xfce_panel_plugin_get_mode(panelPlugin), data)

  self.menu = newMenuWindow(newStore(
      $xfce_panel_plugin_get_property_base(panelPlugin)))
  self.menu.attachWidget = self.button
  self.menu.positionAt = positionMenu
  self.menu.onClosed = onMenuClosed
  self.menu.hostData = data
  g_signal_connect(self.menu.window, "hide", cast[GCallback](onMenuHide),
      data)

proc onRealize(panelPlugin: XfcePanelPlugin, data: pointer) {.cdecl.} =
  if g_object_get_data(panelPlugin, constructedKey) == nil:
    g_object_set_data(panelPlugin, constructedKey, cast[pointer](1))
    construct(panelPlugin)

proc xfce_panel_module_construct(name: cstring, uniqueId: cint,
    displayName, comment: cstring, arguments: ptr cstring,
    screen: GdkScreen): XfcePanelPlugin {.exportc, dynlib, cdecl.} =
  ## Called by xfce4-panel to create one instance of the plugin.
  if screen != nil and name != nil and uniqueId != -1:
    result = cast[XfcePanelPlugin](g_object_new(xfce_panel_plugin_get_type(),
        "name", name, "unique-id", uniqueId, "display-name", displayName,
        "comment", comment, "arguments", arguments, nil))
    g_signal_connect_after(result, "realize", cast[GCallback](onRealize))
