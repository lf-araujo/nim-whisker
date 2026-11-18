## Favorites and recently used launchers, persisted through xfconf in
## upstream Whisker Menu's format (`<property base>/favorites` and
## `<property base>/recent`, arrays of desktop IDs).

import ./[config, glib, xfce]

type
  Store* = ref object
    channel: XfconfChannel
    readOnly: bool
    favorites*, recent*: seq[string]
    favoritesDirty*, recentDirty*: bool

proc readList(channel: XfconfChannel, property: string): seq[string] =
  let list = xfconf_channel_get_string_list(channel, cstring(property))
  if list != nil:
    let items = cast[ptr UncheckedArray[cstring]](list)
    var i = 0
    while items[i] != nil:
      result.add $items[i]
      inc i
    g_strfreev(list)

proc writeList(channel: XfconfChannel, property: string, list: seq[string]) =
  var items = newSeq[cstring](list.len + 1)
  for i, value in list:
    items[i] = cstring(value)
  discard xfconf_channel_set_string_list(channel, cstring(property),
      addr items[0])

proc newStore*(propertyBase = "", readOnly = false): Store =
  ## Opens the store under `propertyBase` in the `xfce4-panel` channel. With
  ## an empty base the lists live in memory only; with `readOnly` they are
  ## loaded but never written back.
  result = Store(readOnly: readOnly)
  for id in defaultFavorites:
    result.favorites.add id
  var error: ptr GError
  if propertyBase.len > 0:
    if xfconf_init(addr error) != 0:
      result.channel = xfconf_channel_new_with_property_base("xfce4-panel",
          cstring(propertyBase))
      if xfconf_channel_has_property(result.channel, "/favorites") != 0:
        result.favorites = readList(result.channel, "/favorites")
      result.recent = readList(result.channel, "/recent")
      if result.recent.len > recentItemsMax:
        result.recent.setLen(recentItemsMax)
    else:
      stderr.writeLine "whisker-nim: xfconf unavailable: " &
          takeMessage(error)

proc save*(store: Store) =
  ## Writes the lists that changed since the last save.
  if store.channel != nil and not store.readOnly:
    if store.favoritesDirty:
      writeList(store.channel, "/favorites", store.favorites)
    if store.recentDirty:
      writeList(store.channel, "/recent", store.recent)
  store.favoritesDirty = false
  store.recentDirty = false

proc addRecent*(store: Store, desktopId: string) =
  ## Moves `desktopId` to the front of the recent list.
  if recentItemsMax > 0 and
      (store.recent.len == 0 or store.recent[0] != desktopId):
    let pos = store.recent.find(desktopId)
    if pos >= 0:
      store.recent.delete(pos)
    store.recent.insert(desktopId, 0)
    if store.recent.len > recentItemsMax:
      store.recent.setLen(recentItemsMax)
    store.recentDirty = true

proc clearRecent*(store: Store) =
  store.recent.setLen(0)
  store.recentDirty = true

proc isFavorite*(store: Store, desktopId: string): bool =
  desktopId in store.favorites

proc addFavorite*(store: Store, desktopId: string) =
  if desktopId notin store.favorites:
    store.favorites.add desktopId
    store.favoritesDirty = true

proc removeFavorite*(store: Store, desktopId: string) =
  let pos = store.favorites.find(desktopId)
  if pos >= 0:
    store.favorites.delete(pos)
    store.favoritesDirty = true
