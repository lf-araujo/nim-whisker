## Cell renderer that draws a launcher icon at a fixed pixel size and asks
## for a wide cell, so icon view items spread across the row. Ported from
## upstream `icon-renderer.cpp`.
##
## The renderer is a GObject subclass of `GtkCellRenderer` registered at run
## time. The class and instance layouts are declared here (GTK 3's ABI is
## frozen) and checked against `g_type_query` before use.

import ./[elements, glib, gtk]

const parentInstanceSize = 32 ## GInitiallyUnowned plus the private pointer.

type
  GObjectClass = object
    gType: GType
    constructProperties: pointer
    constructor, setProperty, getProperty, dispose, finalize: pointer
    dispatchPropertiesChanged, notify, constructed: pointer
    flags, nConstructProperties: csize_t
    pspecs: pointer
    nPspecs: csize_t
    reserved: array[3, pointer]
  SizeFunc = proc (cell: GtkCellRenderer, widget: GtkWidget,
      minimum, natural: ptr cint) {.cdecl.}
  RenderFunc = proc (cell: GtkCellRenderer, cr: Cairo, widget: GtkWidget,
      backgroundArea, cellArea: ptr GdkRectangle, flags: cint) {.cdecl.}
  CellRendererClass = object
    parent: GObjectClass
    getRequestMode: pointer
    getPreferredWidth: SizeFunc
    getPreferredHeightForWidth: pointer
    getPreferredHeight: SizeFunc
    getPreferredWidthForHeight, getAlignedArea, getSize: pointer
    render: RenderFunc
    activate, startEditing, editingCanceled, editingStarted: pointer
    priv: pointer
    reserved: array[3, pointer]
  IconRenderer = object
    parent: array[parentInstanceSize, byte]
    icon: GIcon ## Borrowed from the element of the row being drawn.
    isLauncher: bool
    size: cint

const elementColumn* = 3 ## Model column holding the `Element` pointer.

proc getPreferredWidth(cell: GtkCellRenderer, widget: GtkWidget,
    minimum, natural: ptr cint) {.cdecl.} =
  let renderer = cast[ptr IconRenderer](cell)
  var pad: cint
  gtk_cell_renderer_get_padding(cell, addr pad, nil)
  let width = pad * 2 + renderer.size + 76 - renderer.size div 4
  if minimum != nil:
    minimum[] = width
  if natural != nil:
    natural[] = width * 2 - 1

proc getPreferredHeight(cell: GtkCellRenderer, widget: GtkWidget,
    minimum, natural: ptr cint) {.cdecl.} =
  let renderer = cast[ptr IconRenderer](cell)
  var pad: cint
  gtk_cell_renderer_get_padding(cell, nil, addr pad)
  let height = pad * 2 + renderer.size
  if minimum != nil:
    minimum[] = height
  if natural != nil:
    natural[] = height

proc loadSurface(theme: GtkIconTheme, info: GtkIconInfo,
    window: GdkWindow): CairoSurface =
  if info != nil:
    result = gtk_icon_info_load_surface(info, window, nil)
    g_object_unref(info)

proc render(cell: GtkCellRenderer, cr: Cairo, widget: GtkWidget,
    backgroundArea, cellArea: ptr GdkRectangle, flags: cint) {.cdecl.} =
  let renderer = cast[ptr IconRenderer](cell)
  var clip: GdkRectangle
  if renderer.icon == nil or gdk_cairo_get_clip_rectangle(cr, addr clip) == 0:
    return
  let
    scale = gtk_widget_get_scale_factor(widget)
    theme = gtk_icon_theme_get_for_screen(gtk_widget_get_screen(widget))
    window = gtk_widget_get_window(widget)
    lookupFlags = GTK_ICON_LOOKUP_USE_BUILTIN or GTK_ICON_LOOKUP_FORCE_SIZE
  var surface = loadSurface(theme, gtk_icon_theme_lookup_by_gicon_for_scale(
      theme, renderer.icon, renderer.size, scale, lookupFlags), window)
  if surface == nil:
    let fallback: cstring =
      if renderer.isLauncher: "application-x-executable"
      else: "applications-other"
    surface = loadSurface(theme, gtk_icon_theme_lookup_icon_for_scale(theme,
        fallback, renderer.size, scale, lookupFlags), window)
  if surface != nil:
    var icon, draw: GdkRectangle
    icon.width = cairo_image_surface_get_width(surface) div scale
    icon.height = cairo_image_surface_get_height(surface) div scale
    icon.x = cellArea.x + (cellArea.width - icon.width) div 2
    icon.y = cellArea.y + (cellArea.height - icon.height) div 2
    if gdk_rectangle_intersect(addr clip, addr icon, addr draw) != 0:
      cairo_set_source_surface(cr, surface, cdouble(icon.x), cdouble(icon.y))
      cairo_rectangle(cr, cdouble(draw.x), cdouble(draw.y),
          cdouble(draw.width), cdouble(draw.height))
      cairo_fill(cr)
    cairo_surface_destroy(surface)

proc classInit(klass, classData: pointer) {.cdecl.} =
  let rendererClass = cast[ptr CellRendererClass](klass)
  rendererClass.getPreferredWidth = getPreferredWidth
  rendererClass.getPreferredHeight = getPreferredHeight
  rendererClass.render = render

proc iconRendererType(): GType =
  const typeName = "WhiskerNimIconRenderer"
  result = g_type_from_name(typeName)
  if result == 0:
    var parent: GTypeQuery
    g_type_query(gtk_cell_renderer_get_type(), addr parent)
    doAssert int(parent.classSize) == sizeof(CellRendererClass) and
        int(parent.instanceSize) == parentInstanceSize,
        "GtkCellRenderer layout differs from the one declared here"
    var info = GTypeInfo(classSize: uint16(sizeof(CellRendererClass)),
        classInit: classInit, instanceSize: uint16(sizeof(IconRenderer)))
    result = g_type_register_static(parent.gtype, typeName, addr info, 0)

proc setCellData(layout: GtkWidget, cell: GtkCellRenderer,
    model: GtkTreeModel, iter: ptr GtkTreeIter, data: pointer) {.cdecl.} =
  let renderer = cast[ptr IconRenderer](cell)
  var element: pointer
  gtk_tree_model_get(model, iter, cint(elementColumn), addr element, cint(-1))
  if element != nil:
    renderer.icon = cast[Element](element).icon
    renderer.isLauncher = cast[Element](element).kind == ekLauncher
  else:
    renderer.icon = nil

proc addIconRenderer*(iconView: GtkWidget, size: int) =
  ## Packs an icon renderer into `iconView` that draws the icon of the
  ## `Element` stored in column `elementColumn` of the view's model.
  let cell = cast[GtkCellRenderer](g_object_new(iconRendererType(), nil))
  cast[ptr IconRenderer](cell).size = cint(size)
  g_object_set(cell, "xalign", cdouble(0.5), "yalign", cdouble(1.0), nil)
  gtk_cell_layout_pack_start(iconView, cell, 0)
  gtk_cell_layout_set_cell_data_func(iconView, cell, setCellData, nil, nil)
