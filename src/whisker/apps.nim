## Loads the application menu through garcon and groups launchers into
## categories. Ported from upstream `applications-page.cpp` and
## `category.cpp`, for the flat (non-tree) views only.

import std/[algorithm, tables]
import ./[config, elements, glib, xfce]

type
  Category* = ref object
    name*, tooltip*: string
    icon*: GIcon
    sortKey: string
    items*: seq[Element]
  AppList* = ref object
    menu, settingsMenu: GarconMenu
    categories*: seq[Category] ## Sorted; does not include "All Applications".
    all*: seq[Element] ## Every launcher, sorted by name.
    byId: Table[string, Element]
    stale*: bool ## Set when garcon reports that the menu changed on disk.

proc bySortKey(a, b: Element): int = cmp(a.sortKey, b.sortKey)

proc find*(apps: AppList, desktopId: string): Element =
  ## The launcher with this desktop ID, or `nil`.
  apps.byId.getOrDefault(desktopId)

proc onMenuChanged(source, data: pointer) {.cdecl.} =
  cast[AppList](data).stale = true

proc isA(instance: pointer, gtype: GType): bool =
  g_type_check_instance_is_a(instance, gtype) != 0

proc newCategory(menu: GarconMenu): Category =
  let iconName = toStr(garcon_menu_element_get_icon_name(menu))
  result = Category(name: toStr(garcon_menu_element_get_name(menu)),
      tooltip: toStr(garcon_menu_element_get_comment(menu)),
      icon: newIcon(if iconName.len > 0: iconName else: "applications-other"))
  result.sortKey = takeString(g_utf8_collate_key(cstring(result.name), -1))

proc loadMenu(apps: AppList, menu: GarconMenu, parent: Category,
    settings = false): bool =
  ## Adds the launchers of `menu` to `parent` (`nil` at the top level, where
  ## each submenu becomes a category). Returns whether anything was added.
  let elements = garcon_menu_get_elements(menu)
  var node = elements
  while node != nil:
    if isA(node.data, garcon_menu_item_get_type()):
      let item = cast[GarconMenuItem](node.data)
      g_signal_connect(item, "changed", cast[GCallback](onMenuChanged),
          cast[pointer](apps))
      if garcon_menu_element_get_visible(item) != 0:
        let desktopId = toStr(garcon_menu_item_get_desktop_id(item))
        var launcher = apps.byId.getOrDefault(desktopId)
        if launcher == nil:
          launcher = newLauncher(item)
          apps.byId[desktopId] = launcher
        if settings:
          launcher.isSetting = true
        if parent != nil:
          parent.items.add launcher
        result = true
    elif isA(node.data, garcon_menu_get_type()):
      let
        submenu = cast[GarconMenu](node.data)
        directory = garcon_menu_get_directory(submenu)
      if directory == nil or garcon_menu_directory_get_visible(directory) != 0:
        let category = if parent != nil: parent else: newCategory(submenu)
        if apps.loadMenu(submenu, category, settings):
          if parent == nil:
            apps.categories.add category
          result = true
        elif parent == nil:
          g_object_unref(category.icon)
    node = node.next
  g_list_free(elements)

proc clear(apps: AppList) =
  for launcher in apps.all:
    launcher.release()
  for category in apps.categories:
    g_object_unref(category.icon)
  apps.all.setLen(0)
  apps.categories.setLen(0)
  apps.byId.clear()
  if apps.menu != nil:
    g_object_unref(apps.menu)
    apps.menu = nil
  if apps.settingsMenu != nil:
    g_object_unref(apps.settingsMenu)
    apps.settingsMenu = nil

proc load*(apps: AppList) =
  ## (Re)reads the application menu. Any `Element` or `Category` obtained
  ## from `apps` before this call must be dropped.
  apps.clear()
  apps.stale = false
  garcon_set_environment_xdg("XFCE")
  apps.menu = garcon_menu_new_applications()
  if apps.menu != nil and garcon_menu_load(apps.menu, nil, nil) == 0:
    g_object_unref(apps.menu)
    apps.menu = nil
  if apps.menu != nil:
    g_signal_connect(apps.menu, "reload-required",
        cast[GCallback](onMenuChanged), cast[pointer](apps))
    discard apps.loadMenu(apps.menu, nil)

    # Settings dialogs are searchable but belong to no category.
    let path = xfce_resource_lookup(XFCE_RESOURCE_CONFIG,
        "menus/xfce-settings-manager.menu")
    apps.settingsMenu = garcon_menu_new_for_path(
        if path != nil: path else: cstring(settingsMenuFile))
    g_free(path)
    if apps.settingsMenu != nil:
      g_signal_connect(apps.settingsMenu, "reload-required",
          cast[GCallback](onMenuChanged), cast[pointer](apps))
      if garcon_menu_load(apps.settingsMenu, nil, nil) != 0:
        discard apps.loadMenu(apps.settingsMenu, Category(), settings = true)

    for category in apps.categories:
      category.items.sort(bySortKey)
    if sortCategories:
      apps.categories.sort(
          proc (a, b: Category): int = cmp(a.sortKey, b.sortKey))
    for launcher in apps.byId.values:
      apps.all.add launcher
    apps.all.sort(bySortKey)

proc newAppList*(): AppList =
  ## Creates an empty list; call `load` to fill it.
  AppList(stale: true)
