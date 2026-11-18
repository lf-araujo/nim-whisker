## Minimal hand-written bindings for libxfce4panel (plugin side only).

import ./glib
import ./gtk

{.passL: "-l:libxfce4panel-2.0.so.4".}

type
  XfcePanelPlugin* = ptr object

const
  XFCE_PANEL_PLUGIN_MODE_HORIZONTAL* = cint(0)
  XFCE_PANEL_PLUGIN_MODE_VERTICAL* = cint(1)
  XFCE_PANEL_PLUGIN_MODE_DESKBAR* = cint(2)

{.push importc, cdecl.}
proc xfce_panel_plugin_get_type*(): GType
proc xfce_panel_create_toggle_button*(): GtkWidget
proc xfce_panel_plugin_add_action_widget*(plugin: XfcePanelPlugin,
    widget: GtkWidget)
proc xfce_panel_plugin_block_autohide*(plugin: XfcePanelPlugin,
    blocked: gboolean)
proc xfce_panel_plugin_position_widget*(plugin: XfcePanelPlugin,
    menuWidget, attachWidget: GtkWidget, x, y: ptr cint)
proc xfce_panel_plugin_get_property_base*(plugin: XfcePanelPlugin): cstring
proc xfce_panel_plugin_get_size*(plugin: XfcePanelPlugin): cint
proc xfce_panel_plugin_get_icon_size*(plugin: XfcePanelPlugin): cint
proc xfce_panel_plugin_get_nrows*(plugin: XfcePanelPlugin): cuint
proc xfce_panel_plugin_get_mode*(plugin: XfcePanelPlugin): cint
proc xfce_panel_plugin_get_orientation*(plugin: XfcePanelPlugin): cint
proc xfce_panel_plugin_set_small*(plugin: XfcePanelPlugin, small: gboolean)
{.pop.}
