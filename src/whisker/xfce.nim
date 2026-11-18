## Minimal hand-written bindings for libxfce4util, libxfce4ui, garcon and
## xfconf. The panel library lives in `xfcepanel.nim` so that the standalone
## preview does not link against it.
##
## Libraries are linked by soname (`-l:libfoo.so.N`) so the build works on a
## system that has the runtime packages but not the `-devel` ones.

import ./glib
import ./gtk

{.passL: "-l:libxfce4util.so.7 -l:libxfce4ui-2.so.0".}
{.passL: "-l:libgarcon-1.so.0 -l:libxfconf-0.so.3".}

type
  GarconMenu* = ptr object
  GarconMenuItem* = ptr object
  GarconMenuDirectory* = ptr object
  GarconMenuItemAction* = ptr object
  XfconfChannel* = ptr object

const
  XFCE_RESOURCE_DATA* = cint(0)
  XFCE_RESOURCE_CONFIG* = cint(1)
  settingsMenuFile* = "/etc/xdg/menus/xfce-settings-manager.menu"

{.push importc, cdecl.}
proc xfce_expand_desktop_entry_field_codes*(command: cstring,
    uriList: pointer, icon, name, uri: cstring,
    requiresTerminal: gboolean): cstring
proc xfce_resource_lookup*(kind: cint, filename: cstring): cstring
proc xfce_g_file_set_trusted*(file: GFile, isTrusted: gboolean,
    cancellable: pointer, error: ptr ptr GError): gboolean

proc xfce_spawn*(screen: GdkScreen, workingDirectory: cstring,
    argv, envp: ptr cstring, flags: cint, startupNotify: gboolean,
    startupTimestamp: uint32, startupIconName: cstring,
    childProcess: gboolean, error: ptr ptr GError): gboolean
proc xfce_dialog_show_error*(parent: GtkWidget, error: ptr GError,
    format: cstring) {.varargs.}

proc garcon_set_environment_xdg*(fallbackEnv: cstring)
proc garcon_menu_get_type*(): GType
proc garcon_menu_item_get_type*(): GType
proc garcon_menu_new_applications*(): GarconMenu
proc garcon_menu_new_for_path*(filename: cstring): GarconMenu
proc garcon_menu_load*(menu: GarconMenu, cancellable: pointer,
    error: ptr ptr GError): gboolean
proc garcon_menu_get_elements*(menu: GarconMenu): ptr GList
proc garcon_menu_get_directory*(menu: GarconMenu): GarconMenuDirectory
proc garcon_menu_directory_get_visible*(directory: GarconMenuDirectory):
    gboolean
proc garcon_menu_element_get_name*(element: pointer): cstring
proc garcon_menu_element_get_comment*(element: pointer): cstring
proc garcon_menu_element_get_icon_name*(element: pointer): cstring
proc garcon_menu_element_get_visible*(element: pointer): gboolean
proc garcon_menu_item_get_desktop_id*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_name*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_generic_name*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_comment*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_icon_name*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_command*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_path*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_uri*(item: GarconMenuItem): cstring
proc garcon_menu_item_get_file*(item: GarconMenuItem): GFile
proc garcon_menu_item_get_keywords*(item: GarconMenuItem): ptr GList
proc garcon_menu_item_get_actions*(item: GarconMenuItem): ptr GList
proc garcon_menu_item_get_action*(item: GarconMenuItem, name: cstring):
    GarconMenuItemAction
proc garcon_menu_item_has_category*(item: GarconMenuItem, category: cstring):
    gboolean
proc garcon_menu_item_requires_terminal*(item: GarconMenuItem): gboolean
proc garcon_menu_item_supports_startup_notification*(item: GarconMenuItem):
    gboolean
proc garcon_menu_item_action_get_name*(action: GarconMenuItemAction): cstring
proc garcon_menu_item_action_get_icon_name*(action: GarconMenuItemAction):
    cstring
proc garcon_menu_item_action_get_command*(action: GarconMenuItemAction):
    cstring

proc xfconf_init*(error: ptr ptr GError): gboolean
proc xfconf_channel_new_with_property_base*(channelName,
    propertyBase: cstring): XfconfChannel
proc xfconf_channel_has_property*(channel: XfconfChannel, property: cstring):
    gboolean
proc xfconf_channel_get_string_list*(channel: XfconfChannel,
    property: cstring): ptr cstring
proc xfconf_channel_set_string_list*(channel: XfconfChannel,
    property: cstring, values: ptr cstring): gboolean
{.pop.}
