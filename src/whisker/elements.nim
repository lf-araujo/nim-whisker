## Things that can appear in a launcher view: applications, search actions
## and the "Run <command>" action. Ported from upstream `element.cpp`,
## `launcher.cpp`, `search-action.cpp` and `run-action.cpp`.

import std/strutils
import ./[config, glib, gtk, query, settingskeywords, xfce]

type
  ElementKind* = enum
    ekLauncher, ekSearchAction, ekRunAction
  DesktopAction* = object
    name*, icon*, command*: string
  Element* = ref object
    icon*: GIcon
    text*: string ## Pango markup shown under the icon.
    tooltip*: string
    sortKey*: string
    case kind*: ElementKind
    of ekLauncher:
      item*: GarconMenuItem
      desktopId*, displayName*: string
      isSetting*: bool ## A settings dialog; listed apart in search results.
      searchName, searchGenericName, searchComment, searchCommand: string
      searchKeywords: seq[string]
      actions*: seq[DesktopAction]
    of ekSearchAction:
      spec: SearchActionSpec
      regex: GRegex
      expandedCommand: string
    of ekRunAction:
      commandLine: string

const directionMark = "‎" ## Left-to-right mark, as upstream prepends.

proc normalize*(text: string): string =
  ## Unicode-normalizes and case-folds `text` for searching.
  let normalized = g_utf8_normalize(cstring(text), -1, G_NORMALIZE_DEFAULT)
  if normalized != nil:
    result = takeString(g_utf8_casefold(normalized, -1))
    g_free(normalized)

proc newQuery*(text: string): Query =
  initQuery(text, normalize(text))

proc escapeMarkup(text: string): string =
  takeString(g_markup_escape_text(cstring(text), -1))

proc validText(text: cstring): string =
  if text != nil and g_utf8_validate(text, -1, nil) != 0:
    result = $text

proc setText(element: Element, plain: string) =
  element.text = directionMark & escapeMarkup(plain)
  element.sortKey = takeString(g_utf8_collate_key(cstring(element.text), -1))

proc newIcon*(name: string): GIcon =
  ## Themed icon for a name (dropping an image suffix, as desktop files often
  ## carry one), or a file icon for an absolute path.
  if g_path_is_absolute(cstring(name)) != 0:
    let file = g_file_new_for_path(cstring(name))
    result = g_file_icon_new(file)
    g_object_unref(file)
  else:
    var themed = name
    let dot = name.rfind('.')
    if dot >= 0 and name[dot .. ^1].toLowerAscii() in
        [".png", ".xpm", ".svg", ".svgz"]:
      themed = name[0 ..< dot]
    result = g_themed_icon_new(cstring(themed))

proc release*(element: Element) =
  ## Drops the GObject references held by `element`.
  if element.icon != nil:
    g_object_unref(element.icon)
    element.icon = nil
  if element.kind == ekLauncher and element.item != nil:
    g_object_unref(element.item)
    element.item = nil

proc newLauncher*(item: GarconMenuItem): Element =
  result = Element(kind: ekLauncher, item: cast[GarconMenuItem](
      g_object_ref(item)))
  let iconName = toStr(garcon_menu_item_get_icon_name(item))
  result.icon = newIcon(
      if iconName.len > 0: iconName else: "application-x-executable")
  result.desktopId = toStr(garcon_menu_item_get_desktop_id(item))
  result.displayName = validText(garcon_menu_item_get_name(item))
  let genericName = validText(garcon_menu_item_get_generic_name(item))
  var details = validText(garcon_menu_item_get_comment(item))
  if details.len == 0:
    details = genericName
  result.setText(result.displayName)
  result.tooltip = details
  result.searchName = normalize(result.displayName)
  result.searchGenericName = normalize(genericName)
  result.searchComment = normalize(details)
  var keyword = garcon_menu_item_get_keywords(item)
  while keyword != nil:
    let text = validText(cast[cstring](keyword.data))
    if text.len > 0:
      result.searchKeywords.add normalize(text)
    keyword = keyword.next
  for extra in keywordsFor(result.desktopId).split(';'):
    if extra.len > 0:
      result.searchKeywords.add normalize(extra)
  result.isSetting = garcon_menu_item_has_category(item, "Settings") != 0
  result.searchCommand = normalize(
      validText(garcon_menu_item_get_command(item)))
  let actionNames = garcon_menu_item_get_actions(item)
  var actionName = actionNames
  while actionName != nil:
    let action = garcon_menu_item_get_action(item,
        cast[cstring](actionName.data))
    if action != nil:
      result.actions.add DesktopAction(
          name: toStr(garcon_menu_item_action_get_name(action)),
          icon: toStr(garcon_menu_item_action_get_icon_name(action)),
          command: toStr(garcon_menu_item_action_get_command(action)))
    actionName = actionName.next
  g_list_free(actionNames)

proc newSearchAction*(spec: SearchActionSpec): Element =
  result = Element(kind: ekSearchAction, spec: spec,
      icon: newIcon("folder-saved-search"), tooltip: "Search Action")
  result.setText(spec.name)

proc newRunAction*(): Element =
  Element(kind: ekRunAction, icon: newIcon("system-run"))

func isRegex*(element: Element): bool =
  element.kind == ekSearchAction and element.spec.isRegex

func pattern*(element: Element): string = element.spec.pattern

proc spawn(screen: GdkScreen, command, workingDirectory: string,
    startupNotify: bool, iconName: string) =
  var
    error: ptr GError
    argv: ptr cstring
    ok = false
  if g_shell_parse_argv(cstring(command), nil, addr argv, addr error) != 0:
    ok = xfce_spawn(screen,
        if workingDirectory.len > 0: cstring(workingDirectory) else: nil,
        argv, nil, G_SPAWN_SEARCH_PATH, gboolean(startupNotify),
        gtk_get_current_event_time(),
        if iconName.len > 0: cstring(iconName) else: nil, 1, addr error) != 0
    g_strfreev(argv)
  if not ok:
    xfce_dialog_show_error(nil, error, "Failed to execute command \"%s\".",
        cstring(command))
    if error != nil:
      g_error_free(error)

proc runLauncher(element: Element, screen: GdkScreen, command, icon,
    name: string, requiresTerminal: bool) =
  if command.len > 0:
    let
      uri = garcon_menu_item_get_uri(element.item)
      expanded = takeString(xfce_expand_desktop_entry_field_codes(
          cstring(command), nil, if icon.len > 0: cstring(icon) else: nil,
          cstring(name), uri, gboolean(requiresTerminal)))
    g_free(uri)
    spawn(screen, expanded, toStr(garcon_menu_item_get_path(element.item)),
        garcon_menu_item_supports_startup_notification(element.item) != 0,
        icon)

proc run*(element: Element, screen: GdkScreen) =
  ## Launches the application or runs the action.
  case element.kind
  of ekLauncher:
    let item = element.item
    runLauncher(element, screen, toStr(garcon_menu_item_get_command(item)),
        toStr(garcon_menu_item_get_icon_name(item)),
        toStr(garcon_menu_item_get_name(item)),
        garcon_menu_item_requires_terminal(item) != 0)
  of ekSearchAction:
    spawn(screen, element.expandedCommand, "", false, "")
  of ekRunAction:
    spawn(screen, element.commandLine, "", false, "")

proc runAction*(element: Element, screen: GdkScreen, action: DesktopAction) =
  ## Runs one of a launcher's desktop actions (e.g. "New Private Window").
  runLauncher(element, screen, action.command, action.icon, action.name,
      false)

proc uri*(element: Element): string =
  takeString(garcon_menu_item_get_uri(element.item))

proc expandPrefixCommand(command, haystack, trimmed: string): string =
  ## Expands `%s` (trimmed query), `%S` (full query), `%u` (URI-escaped
  ## query) and `%%` in a search action command.
  var i = 0
  while i < command.len:
    if command[i] == '%' and i + 1 < command.len:
      case command[i + 1]
      of 's': result.add trimmed
      of 'S': result.add haystack
      of 'u':
        result.add takeString(g_uri_escape_string(cstring(trimmed), nil, 1))
      of '%': result.add '%'
      else: discard
      i += 2
    else:
      result.add command[i]
      inc i

proc matchSearchAction(element: Element, haystack: string): uint32 =
  result = noMatch
  let spec = element.spec
  if spec.pattern.len == 0 or spec.command.len == 0:
    return
  element.expandedCommand = ""
  if not spec.isRegex:
    if haystack.startsWith(spec.pattern):
      element.expandedCommand = expandPrefixCommand(spec.command, haystack,
          haystack[spec.pattern.len .. ^1].strip())
      result = uint32(spec.pattern.len)
  else:
    if element.regex == nil:
      element.regex = g_regex_new(cstring(spec.pattern), G_REGEX_OPTIMIZE, 0,
          nil)
    if element.regex != nil:
      var info: GMatchInfo
      if g_regex_match(element.regex, cstring(haystack), 0, addr info) != 0:
        let expanded = g_match_info_expand_references(info,
            cstring(spec.command), nil)
        if expanded != nil:
          element.expandedCommand = takeString(expanded)
          result = uint32(spec.pattern.len)
      if info != nil:
        g_match_info_free(info)

proc matchRunAction(element: Element, raw: string): uint32 =
  ## Offers "Run <command>" when the first word is a program in `PATH`.
  result = noMatch
  var argv: ptr cstring
  if g_shell_parse_argv(cstring(raw), nil, addr argv, nil) != 0:
    let path = g_find_program_in_path(cast[ptr UncheckedArray[cstring]](
        argv)[0])
    if path != nil:
      g_free(path)
      element.commandLine = raw
      element.tooltip = "Run " & raw
      element.setText(element.tooltip)
      # After matches in names, before matches in executables.
      result = 0xFFF
    g_strfreev(argv)

proc search*(element: Element, query: Query): uint32 =
  ## Relevancy of `element` for `query` (lower sorts first), or `noMatch`.
  case element.kind
  of ekSearchAction:
    return matchSearchAction(element, query.raw)
  of ekRunAction:
    return matchRunAction(element, query.raw)
  of ekLauncher:
    var relevancy = query.match(element.searchName)
    if relevancy == noMatch:
      relevancy = query.matchAsCharacters(element.searchName)
    if relevancy != noMatch:
      return relevancy or 0x400
    relevancy = query.match(element.searchGenericName)
    if relevancy != noMatch:
      return relevancy or 0x800
    relevancy = query.match(element.searchComment)
    if relevancy != noMatch:
      return relevancy or 0x1000
    for keyword in element.searchKeywords:
      relevancy = query.match(keyword)
      if relevancy != noMatch:
        return relevancy or 0x2000
    relevancy = query.match(element.searchCommand)
    if relevancy != noMatch:
      return relevancy or 0x4000
    return noMatch
