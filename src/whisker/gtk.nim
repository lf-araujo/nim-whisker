## Minimal hand-written bindings for GTK 3, GDK, cairo and gtk-layer-shell.
##
## Only what whisker-nim uses is declared, under the C names. All widget
## classes share the `GtkWidget` handle type: GTK checks the real class at
## run time, and one handle type keeps the menu code free of casts.

import ./glib

{.passL: "-l:libgtk-3.so.0 -l:libgdk-3.so.0 -l:libcairo.so.2".}
{.passL: "-l:libgtk-layer-shell.so.0".}

type
  GtkWidget* = ptr object
  GtkTreeModel* = ptr object
  GtkTreePath* = ptr object
  GtkCellRenderer* = ptr object
  GtkStyleContext* = ptr object
  GtkAdjustment* = ptr object
  GtkIconTheme* = ptr object
  GtkIconInfo* = ptr object
  GdkScreen* = ptr object
  GdkVisual* = ptr object
  GdkDisplay* = ptr object
  GdkMonitor* = ptr object
  GdkWindow* = ptr object
  GdkEvent* = ptr object
  Cairo* = ptr object
  CairoSurface* = ptr object
  GtkTreeIter* = object
    stamp*: cint
    userData*, userData2*, userData3*: pointer
  GdkRectangle* = object
    x*, y*, width*, height*: cint
  GtkRequisition* = object
    width*, height*: cint
  GtkAllocation* = object
    x*, y*, width*, height*: cint
  GtkCellDataFunc* = proc (layout: GtkWidget, cell: GtkCellRenderer,
      model: GtkTreeModel, iter: ptr GtkTreeIter, data: pointer) {.cdecl.}

const
  GTK_WINDOW_TOPLEVEL* = cint(0)
  GDK_WINDOW_TYPE_HINT_MENU* = cint(2)
  GDK_GRAVITY_NORTH_WEST* = cint(1)
  GDK_GRAVITY_SOUTH_WEST* = cint(7)
  GDK_FOCUS_CHANGE_MASK* = cint(1 shl 14)
  GDK_STRUCTURE_MASK* = cint(1 shl 15)
  GDK_SCROLL_MASK* = cint(1 shl 21)
  GDK_BUTTON_PRESS* = cint(4)
  GTK_SHADOW_NONE* = cint(0)
  GTK_SHADOW_OUT* = cint(2)
  GTK_SHADOW_ETCHED_IN* = cint(3)
  GTK_ORIENTATION_HORIZONTAL* = cint(0)
  GTK_ORIENTATION_VERTICAL* = cint(1)
  GTK_POLICY_AUTOMATIC* = cint(1)
  GTK_POLICY_NEVER* = cint(2)
  GTK_RELIEF_NONE* = cint(2)
  GTK_ICON_SIZE_MENU* = cint(1)
  GTK_ICON_SIZE_LARGE_TOOLBAR* = cint(3)
  GTK_ICON_SIZE_BUTTON* = cint(4)
  GTK_ICON_SIZE_DIALOG* = cint(6)
  GTK_SELECTION_SINGLE* = cint(1)
  GTK_SELECTION_BROWSE* = cint(2)
  GTK_ALIGN_START* = cint(1)
  GTK_ALIGN_CENTER* = cint(3)
  PANGO_ELLIPSIZE_MIDDLE* = cint(2)
  GTK_PACK_START* = cint(0)
  GTK_MESSAGE_INFO* = cint(0)
  GTK_MESSAGE_QUESTION* = cint(2)
  GTK_BUTTONS_CANCEL* = cint(3)
  GTK_RESPONSE_ACCEPT* = cint(-3)
  GTK_TEXT_DIR_RTL* = cint(2)
  GTK_ICON_LOOKUP_USE_BUILTIN* = cint(1 shl 2)
  GTK_ICON_LOOKUP_FORCE_SIZE* = cint(1 shl 4)
  CAIRO_FORMAT_ARGB32* = cint(0)
  CAIRO_OPERATOR_SOURCE* = cint(1)
  GTK_LAYER_SHELL_EDGE_LEFT* = cint(0)
  GTK_LAYER_SHELL_EDGE_RIGHT* = cint(1)
  GTK_LAYER_SHELL_EDGE_TOP* = cint(2)
  GTK_LAYER_SHELL_EDGE_BOTTOM* = cint(3)
  GTK_LAYER_SHELL_LAYER_OVERLAY* = cint(3)
  GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND* = cint(2)
  GDK_KEY_Escape* = cuint(0xff1b)
  GDK_KEY_BackSpace* = cuint(0xff08)
  GDK_KEY_Tab* = cuint(0xff09)
  GDK_KEY_Return* = cuint(0xff0d)
  GDK_KEY_Home* = cuint(0xff50)
  GDK_KEY_End* = cuint(0xff57)
  GDK_KEY_KP_Enter* = cuint(0xff8d)
  GDK_KEY_ISO_Left_Tab* = cuint(0xfe20)
  GDK_KEY_Left* = cuint(0xff51)
  GDK_KEY_Up* = cuint(0xff52)
  GDK_KEY_Right* = cuint(0xff53)
  GDK_KEY_Down* = cuint(0xff54)
  GDK_KEY_Page_Up* = cuint(0xff55)
  GDK_KEY_Page_Down* = cuint(0xff56)
  GDK_KEY_KP_Left* = cuint(0xff96)
  GDK_KEY_KP_Up* = cuint(0xff97)
  GDK_KEY_KP_Right* = cuint(0xff98)
  GDK_KEY_KP_Down* = cuint(0xff99)
  GDK_KEY_KP_Page_Up* = cuint(0xff9a)
  GDK_KEY_KP_Page_Down* = cuint(0xff9b)

{.push importc, cdecl.}
proc gtk_init*(argc: ptr cint, argv: pointer)
proc gtk_main*()
proc gtk_main_quit*()
proc gtk_events_pending*(): gboolean
proc gtk_main_iteration*(): gboolean
proc gtk_get_current_event_time*(): uint32

proc gtk_window_new*(kind: cint): GtkWidget
proc gtk_window_set_title*(window: GtkWidget, title: cstring)
proc gtk_window_set_modal*(window: GtkWidget, modal: gboolean)
proc gtk_window_set_decorated*(window: GtkWidget, setting: gboolean)
proc gtk_window_set_deletable*(window: GtkWidget, setting: gboolean)
proc gtk_window_set_skip_taskbar_hint*(window: GtkWidget, setting: gboolean)
proc gtk_window_set_skip_pager_hint*(window: GtkWidget, setting: gboolean)
proc gtk_window_set_type_hint*(window: GtkWidget, hint: cint)
proc gtk_window_set_keep_above*(window: GtkWidget, setting: gboolean)
proc gtk_window_set_titlebar*(window, titlebar: GtkWidget)
proc gtk_window_stick*(window: GtkWidget)
proc gtk_window_present*(window: GtkWidget)
proc gtk_window_resize*(window: GtkWidget, width, height: cint)
proc gtk_window_move*(window: GtkWidget, x, y: cint)
proc gtk_window_get_position*(window: GtkWidget, x, y: ptr cint)
proc gtk_window_get_focus*(window: GtkWidget): GtkWidget
proc gtk_window_propagate_key_event*(window: GtkWidget,
    event: GdkEvent): gboolean

proc gtk_widget_set_name*(widget: GtkWidget, name: cstring)
proc gtk_widget_add_events*(widget: GtkWidget, events: cint)
proc gtk_widget_show*(widget: GtkWidget)
proc gtk_widget_show_all*(widget: GtkWidget)
proc gtk_widget_hide*(widget: GtkWidget)
proc gtk_widget_hide_on_delete*(widget: GtkWidget): gboolean
proc gtk_widget_set_visible*(widget: GtkWidget, visible: gboolean)
proc gtk_widget_get_visible*(widget: GtkWidget): gboolean
proc gtk_widget_destroy*(widget: GtkWidget)
proc gtk_widget_grab_focus*(widget: GtkWidget)
proc gtk_widget_set_size_request*(widget: GtkWidget, width, height: cint)
proc gtk_widget_get_preferred_size*(widget: GtkWidget,
    minimum, natural: ptr GtkRequisition)
proc gtk_widget_get_style_context*(widget: GtkWidget): GtkStyleContext
proc gtk_widget_set_app_paintable*(widget: GtkWidget, paintable: gboolean)
proc gtk_widget_get_screen*(widget: GtkWidget): GdkScreen
proc gtk_widget_get_display*(widget: GtkWidget): GdkDisplay
proc gtk_widget_get_window*(widget: GtkWidget): GdkWindow
proc gtk_widget_get_parent*(widget: GtkWidget): GtkWidget
proc gtk_widget_get_toplevel*(widget: GtkWidget): GtkWidget
proc gtk_widget_set_visual*(widget: GtkWidget, visual: GdkVisual)
proc gtk_widget_get_realized*(widget: GtkWidget): gboolean
proc gtk_widget_realize*(widget: GtkWidget)
proc gtk_widget_get_allocated_width*(widget: GtkWidget): cint
proc gtk_widget_get_allocated_height*(widget: GtkWidget): cint
proc gtk_widget_get_scale_factor*(widget: GtkWidget): cint
proc gtk_widget_get_default_direction*(): cint
proc gtk_widget_set_tooltip_text*(widget: GtkWidget, text: cstring)
proc gtk_widget_set_tooltip_markup*(widget: GtkWidget, markup: cstring)
proc gtk_widget_set_has_tooltip*(widget: GtkWidget, hasTooltip: gboolean)
proc gtk_widget_set_focus_on_click*(widget: GtkWidget, setting: gboolean)
proc gtk_widget_set_sensitive*(widget: GtkWidget, sensitive: gboolean)
proc gtk_widget_set_halign*(widget: GtkWidget, align: cint)
proc gtk_widget_set_valign*(widget: GtkWidget, align: cint)
proc gtk_widget_set_hexpand*(widget: GtkWidget, expand: gboolean)
proc gtk_widget_set_vexpand*(widget: GtkWidget, expand: gboolean)

proc gtk_container_add*(container, widget: GtkWidget)
proc gtk_container_remove*(container, widget: GtkWidget)
proc gtk_container_set_border_width*(container: GtkWidget, width: cuint)
proc gtk_frame_new*(label: cstring): GtkWidget
proc gtk_frame_set_shadow_type*(frame: GtkWidget, kind: cint)
proc gtk_box_new*(orientation, spacing: cint): GtkWidget
proc gtk_box_pack_start*(box, child: GtkWidget, expand, fill: gboolean,
    padding: cuint)
proc gtk_box_set_center_widget*(box, widget: GtkWidget)
proc gtk_box_set_child_packing*(box, child: GtkWidget,
    expand, fill: gboolean, padding: cuint, packType: cint)
proc gtk_orientable_set_orientation*(orientable: GtkWidget, orientation: cint)
proc gtk_grid_new*(): GtkWidget
proc gtk_grid_attach*(grid, child: GtkWidget, left, top, width, height: cint)
proc gtk_grid_set_row_spacing*(grid: GtkWidget, spacing: cuint)
proc gtk_grid_set_column_spacing*(grid: GtkWidget, spacing: cuint)
proc gtk_stack_new*(): GtkWidget
proc gtk_stack_add_named*(stack, child: GtkWidget, name: cstring)
proc gtk_stack_set_visible_child_name*(stack: GtkWidget, name: cstring)
proc gtk_stack_get_visible_child_name*(stack: GtkWidget): cstring
proc gtk_scrolled_window_new*(hadjustment, vadjustment: GtkAdjustment):
    GtkWidget
proc gtk_scrolled_window_set_policy*(window: GtkWidget, hpolicy, vpolicy: cint)
proc gtk_scrolled_window_set_shadow_type*(window: GtkWidget, kind: cint)
proc gtk_scrollable_get_vadjustment*(scrollable: GtkWidget): GtkAdjustment
proc gtk_adjustment_get_lower*(adjustment: GtkAdjustment): cdouble
proc gtk_adjustment_set_value*(adjustment: GtkAdjustment, value: cdouble)
proc gtk_separator_new*(orientation: cint): GtkWidget
proc gtk_drawing_area_new*(): GtkWidget

proc gtk_search_entry_new*(): GtkWidget
proc gtk_entry_get_text*(entry: GtkWidget): cstring
proc gtk_entry_set_text*(entry: GtkWidget, text: cstring)
proc gtk_entry_get_text_length*(entry: GtkWidget): uint16
proc gtk_entry_grab_focus_without_selecting*(entry: GtkWidget)
proc gtk_editable_get_position*(editable: GtkWidget): cint

proc gtk_button_new*(): GtkWidget
proc gtk_button_set_relief*(button: GtkWidget, relief: cint)
proc gtk_button_set_image*(button, image: GtkWidget)
proc gtk_radio_button_new*(group: pointer): GtkWidget
proc gtk_radio_button_join_group*(button, groupSource: GtkWidget)
proc gtk_toggle_button_set_mode*(button: GtkWidget, drawIndicator: gboolean)
proc gtk_toggle_button_set_active*(button: GtkWidget, active: gboolean)
proc gtk_toggle_button_get_active*(button: GtkWidget): gboolean
proc gtk_image_new*(): GtkWidget
proc gtk_image_new_from_gicon*(icon: GIcon, size: cint): GtkWidget
proc gtk_image_new_from_icon_name*(iconName: cstring, size: cint): GtkWidget
proc gtk_image_set_from_icon_name*(image: GtkWidget, iconName: cstring,
    size: cint)
proc gtk_image_set_from_gicon*(image: GtkWidget, icon: GIcon, size: cint)
proc gtk_scrolled_window_get_vadjustment*(window: GtkWidget): GtkAdjustment
proc gtk_adjustment_get_value*(adjustment: GtkAdjustment): cdouble
proc gtk_adjustment_get_page_size*(adjustment: GtkAdjustment): cdouble
proc gtk_image_set_pixel_size*(image: GtkWidget, pixelSize: cint)
proc gtk_label_new*(str: cstring): GtkWidget
proc gtk_label_set_markup*(label: GtkWidget, str: cstring)
proc gtk_label_set_angle*(label: GtkWidget, angle: cdouble)
proc gtk_label_set_ellipsize*(label: GtkWidget, mode: cint)
proc gtk_label_set_xalign*(label: GtkWidget, xalign: cfloat)
proc gtk_list_box_new*(): GtkWidget
proc gtk_list_box_insert*(box, child: GtkWidget, position: cint)
proc gtk_list_box_get_row_at_y*(box: GtkWidget, y: cint): GtkWidget
proc gtk_list_box_select_row*(box, row: GtkWidget)
proc gtk_list_box_get_selected_row*(box: GtkWidget): GtkWidget
proc gtk_list_box_row_get_index*(row: GtkWidget): cint
proc gtk_info_bar_new*(): GtkWidget
proc gtk_info_bar_set_message_type*(infoBar: GtkWidget, messageType: cint)
proc gtk_info_bar_get_content_area*(infoBar: GtkWidget): GtkWidget

proc gtk_icon_view_new*(): GtkWidget
proc gtk_icon_view_set_model*(iconView: GtkWidget, model: GtkTreeModel)
proc gtk_icon_view_get_model*(iconView: GtkWidget): GtkTreeModel
proc gtk_icon_view_set_markup_column*(iconView: GtkWidget, column: cint)
proc gtk_icon_view_set_tooltip_column*(iconView: GtkWidget, column: cint)
proc gtk_icon_view_set_activate_on_single_click*(iconView: GtkWidget,
    single: gboolean)
proc gtk_icon_view_set_selection_mode*(iconView: GtkWidget, mode: cint)
proc gtk_icon_view_set_item_padding*(iconView: GtkWidget, padding: cint)
proc gtk_icon_view_get_cursor*(iconView: GtkWidget, path: ptr GtkTreePath,
    cell: ptr GtkCellRenderer): gboolean
proc gtk_icon_view_set_cursor*(iconView: GtkWidget, path: GtkTreePath,
    cell: GtkCellRenderer, startEditing: gboolean)
proc gtk_icon_view_get_path_at_pos*(iconView: GtkWidget, x, y: cint):
    GtkTreePath
proc gtk_icon_view_get_selected_items*(iconView: GtkWidget): ptr GList
proc gtk_icon_view_path_is_selected*(iconView: GtkWidget,
    path: GtkTreePath): gboolean
proc gtk_icon_view_item_activated*(iconView: GtkWidget, path: GtkTreePath)
proc gtk_icon_view_scroll_to_path*(iconView: GtkWidget, path: GtkTreePath,
    useAlign: gboolean, rowAlign, colAlign: cfloat)
proc gtk_icon_view_select_path*(iconView: GtkWidget, path: GtkTreePath)
proc gtk_icon_view_unselect_all*(iconView: GtkWidget)
proc gtk_cell_layout_pack_start*(layout: GtkWidget, cell: GtkCellRenderer,
    expand: gboolean)
proc gtk_cell_layout_set_cell_data_func*(layout: GtkWidget,
    cell: GtkCellRenderer, function: GtkCellDataFunc, data: pointer,
    destroy: pointer)
proc gtk_cell_renderer_get_type*(): GType
proc gtk_cell_renderer_get_padding*(cell: GtkCellRenderer,
    xpad, ypad: ptr cint)

proc gtk_list_store_newv*(nColumns: cint, types: ptr GType): GtkTreeModel
proc gtk_list_store_insert_with_values*(store: GtkTreeModel,
    iter: ptr GtkTreeIter, position: cint) {.varargs.}
proc gtk_tree_model_get*(model: GtkTreeModel, iter: ptr GtkTreeIter)
    {.varargs.}
proc gtk_tree_model_get_iter*(model: GtkTreeModel, iter: ptr GtkTreeIter,
    path: GtkTreePath): gboolean
proc gtk_tree_model_get_iter_first*(model: GtkTreeModel,
    iter: ptr GtkTreeIter): gboolean
proc gtk_tree_model_get_path*(model: GtkTreeModel, iter: ptr GtkTreeIter):
    GtkTreePath
proc gtk_tree_model_iter_next*(model: GtkTreeModel, iter: ptr GtkTreeIter): gboolean
proc gtk_tree_path_copy*(path: GtkTreePath): GtkTreePath
proc gtk_tree_path_free*(path: GtkTreePath)
proc gtk_tree_path_get_indices*(path: GtkTreePath): ptr cint

proc gtk_style_context_add_class*(context: GtkStyleContext, name: cstring)
proc gtk_render_background*(context: GtkStyleContext, cr: Cairo,
    x, y, width, height: cdouble)

proc gtk_menu_new*(): GtkWidget
proc gtk_menu_item_new_with_label*(label: cstring): GtkWidget
proc gtk_image_menu_item_new_with_label*(label: cstring): GtkWidget
proc gtk_image_menu_item_set_image*(item, image: GtkWidget)
proc gtk_separator_menu_item_new*(): GtkWidget
proc gtk_menu_shell_append*(shell, child: GtkWidget)
proc gtk_menu_attach_to_widget*(menu, attachWidget: GtkWidget,
    detacher: pointer)
proc gtk_menu_popup_at_pointer*(menu: GtkWidget, triggerEvent: GdkEvent)
proc gtk_menu_popup_at_widget*(menu, widget: GtkWidget,
    widgetAnchor, menuAnchor: cint, triggerEvent: GdkEvent)
proc gtk_menu_popup_at_rect*(menu: GtkWidget, rectWindow: GdkWindow,
    rect: ptr GdkRectangle, rectAnchor, menuAnchor: cint,
    triggerEvent: GdkEvent)
proc gtk_menu_shell_select_item*(menu: GtkWidget, item: GtkWidget)
proc gtk_menu_shell_select_first*(menu: GtkWidget, searchSensitive: gboolean)
proc gtk_menu_item_set_submenu*(item, submenu: GtkWidget)
proc gtk_icon_view_get_cell_rect*(iconView: GtkWidget, path: GtkTreePath,
    cell: GtkCellRenderer, rect: ptr GdkRectangle): gboolean
proc gtk_icon_view_get_item_row*(iconView: GtkWidget, path: GtkTreePath): cint
proc gtk_list_box_unselect_all*(box: GtkWidget)
proc gtk_tree_model_iter_n_children*(model: GtkTreeModel,
    iter: ptr GtkTreeIter): cint
proc gtk_tree_path_new_from_indices*(firstIndex: cint): GtkTreePath {.varargs.}
proc gdk_atom_intern*(atomName: cstring, onlyIfExists: gboolean): pointer
proc gtk_container_get_children*(container: GtkWidget): ptr GList
proc gtk_widget_translate_coordinates*(srcWidget, destWidget: GtkWidget,
    srcX, srcY: cint, destX, destY: ptr cint)
proc gtk_widget_get_allocation*(widget: GtkWidget, allocation: ptr GtkAllocation)
proc gtk_clipboard_get*(selection: pointer): GtkWidget
proc gtk_clipboard_set_text*(clipboard: GtkWidget, text: cstring, len: cint)
proc g_filename_to_uri*(filename: cstring, hostname, error: pointer): cstring

proc gtk_message_dialog_new*(parent: GtkWidget, flags, messageType,
    buttons: cint, format: cstring): GtkWidget {.varargs.}
proc gtk_message_dialog_format_secondary_text*(dialog: GtkWidget,
    format: cstring) {.varargs.}
proc gtk_message_dialog_set_image*(dialog, image: GtkWidget)
proc gtk_dialog_add_button*(dialog: GtkWidget, text: cstring,
    responseId: cint): GtkWidget
proc gtk_dialog_set_default_response*(dialog: GtkWidget, responseId: cint)
proc gtk_dialog_run*(dialog: GtkWidget): cint
proc gtk_dialog_response*(dialog: GtkWidget, responseId: cint)
proc gtk_header_bar_new*(): GtkWidget
proc gtk_header_bar_set_has_subtitle*(bar: GtkWidget, setting: gboolean)
proc gtk_header_bar_set_show_close_button*(bar: GtkWidget, setting: gboolean)

proc gtk_icon_theme_get_default*(): GtkIconTheme
proc gtk_icon_theme_get_for_screen*(screen: GdkScreen): GtkIconTheme
proc gtk_icon_theme_has_icon*(theme: GtkIconTheme, iconName: cstring):
    gboolean
proc gtk_icon_theme_lookup_by_gicon_for_scale*(theme: GtkIconTheme,
    icon: GIcon, size, scale, flags: cint): GtkIconInfo
proc gtk_icon_theme_lookup_icon_for_scale*(theme: GtkIconTheme,
    iconName: cstring, size, scale, flags: cint): GtkIconInfo
proc gtk_icon_info_load_surface*(info: GtkIconInfo, forWindow: GdkWindow,
    error: ptr ptr GError): CairoSurface

proc gdk_screen_get_rgba_visual*(screen: GdkScreen): GdkVisual
proc gdk_screen_get_system_visual*(screen: GdkScreen): GdkVisual
proc gdk_screen_is_composited*(screen: GdkScreen): gboolean
proc gdk_display_get_default*(): GdkDisplay
proc gdk_display_get_monitor*(display: GdkDisplay, monitorNum: cint):
    GdkMonitor
proc gdk_display_get_monitor_at_window*(display: GdkDisplay,
    window: GdkWindow): GdkMonitor
proc gdk_monitor_get_geometry*(monitor: GdkMonitor,
    geometry: ptr GdkRectangle)
proc gdk_event_get_keyval*(event: GdkEvent, keyval: ptr cuint): gboolean
proc gdk_event_get_coords*(event: GdkEvent, x, y: ptr cdouble): gboolean
proc gdk_event_get_button*(event: GdkEvent, button: ptr cuint): gboolean
proc gdk_event_get_event_type*(event: GdkEvent): cint
proc gdk_event_triggers_context_menu*(event: GdkEvent): gboolean
proc gdk_cairo_get_clip_rectangle*(cr: Cairo, rect: ptr GdkRectangle):
    gboolean
proc gdk_rectangle_intersect*(src1, src2, dest: ptr GdkRectangle): gboolean

proc cairo_image_surface_create*(format, width, height: cint): CairoSurface
proc cairo_image_surface_get_width*(surface: CairoSurface): cint
proc cairo_image_surface_get_height*(surface: CairoSurface): cint
proc cairo_surface_destroy*(surface: CairoSurface)
proc cairo_create*(target: CairoSurface): Cairo
proc cairo_destroy*(cr: Cairo)
proc cairo_set_operator*(cr: Cairo, op: cint)
proc cairo_set_source_surface*(cr: Cairo, surface: CairoSurface,
    x, y: cdouble)
proc cairo_paint_with_alpha*(cr: Cairo, alpha: cdouble)
proc cairo_rectangle*(cr: Cairo, x, y, width, height: cdouble)
proc cairo_fill*(cr: Cairo)

proc gtk_layer_is_supported*(): gboolean
proc gtk_layer_init_for_window*(window: GtkWidget)
proc gtk_layer_set_namespace*(window: GtkWidget, name: cstring)
proc gtk_layer_set_exclusive_zone*(window: GtkWidget, zone: cint)
proc gtk_layer_set_anchor*(window: GtkWidget, edge: cint, anchor: gboolean)
proc gtk_layer_set_margin*(window: GtkWidget, edge, margin: cint)
proc gtk_layer_set_keyboard_mode*(window: GtkWidget, mode: cint)
proc gtk_layer_set_layer*(window: GtkWidget, layer: cint)
proc gtk_layer_set_monitor*(window: GtkWidget, monitor: GdkMonitor)
{.pop.}

proc addClass*(widget: GtkWidget, name: cstring) =
  gtk_style_context_add_class(gtk_widget_get_style_context(widget), name)

proc isModifier*(keyEvent: GdkEvent): bool =
  ## Reads the `is_modifier` bit of a `GdkEventKey`. GDK 3 has no accessor for
  ## it; the bit sits at byte 51 of the struct on LP64 (after `group`).
  (cast[ptr UncheckedArray[uint8]](keyEvent)[51] and 1) != 0
