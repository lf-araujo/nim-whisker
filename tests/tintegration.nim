## Integration checks that need a display and the Xfce libraries: spawning,
## search action expansion, application loading and xfconf persistence.
## Uses the throwaway xfconf property base /whisker-nim-test.

import std/[os, strutils, unittest]
import ../src/whisker/[apps, config, elements, filesearch, glib, gtk, query,
  search, store]

gtk_init(nil, nil)
let screen = gtk_widget_get_screen(gtk_window_new(GTK_WINDOW_TOPLEVEL))

suite "elements":
  test "run action spawns a program from PATH":
    let
      marker = getTempDir() / "whisker-nim-spawn-test"
      action = newRunAction()
    removeFile(marker)
    check action.search(newQuery("touch " & marker)) == 0xFFF
    action.run(screen)
    for _ in 0 ..< 50:
      if not fileExists(marker):
        sleep(20)
    check fileExists(marker)
    removeFile(marker)
    check action.search(newQuery("no-such-program-zz")) == noMatch

  test "search actions match by prefix and regex":
    let wiki = newSearchAction(searchActions[3])
    check wiki.search(newQuery("!w nim lang")) == 2
    check wiki.search(newQuery("nim")) == noMatch
    let uri = newSearchAction(searchActions[5])
    check uri.isRegex
    check uri.search(newQuery("https://nim-lang.org")) != noMatch
    check uri.search(newQuery("nim-lang.org")) == noMatch

suite "apps":
  test "loads launchers and categories":
    let list = newAppList()
    list.load()
    check list.all.len > 10
    check list.categories.len > 3
    check list.find(list.all[0].desktopId) == list.all[0]
    check list.find("no-such.desktop") == nil

  test "search ranks a name match first":
    let list = newAppList()
    list.load()
    let s = newSearch()
    s.setLaunchers(list.all)
    var noResults: bool
    let results = s.update("settings manager", noResults)
    check not noResults
    check results.len > 0
    check results[0].kind == ekLauncher
    discard s.update("zzqqzz", noResults)
    check noResults

  test "settings dialogs are flagged and found by what they control":
    let list = newAppList()
    list.load()
    let display = list.find("xfce-display-settings.desktop")
    check display != nil and display.isSetting
    # "monitor" is not in the dialog's own name; it comes from its keywords.
    check display.search(newQuery("monitor")) != noMatch
    let network = list.find("nm-connection-editor.desktop")
    if network != nil:
      # This dialog declares no keywords; "wifi" is one of ours.
      check network.search(newQuery("wifi")) != noMatch
    var flagged = 0
    for launcher in list.all:
      if launcher.isSetting:
        inc flagged
    check flagged > 5 and flagged < list.all.len

suite "store":
  test "round-trips through xfconf":
    let a = newStore("/whisker-nim-test")
    a.addRecent("b.desktop")
    a.addRecent("a.desktop")
    a.addRecent("b.desktop")
    a.addFavorite("x.desktop")
    a.save()
    let b = newStore("/whisker-nim-test")
    check b.recent == @["b.desktop", "a.desktop"]
    check b.isFavorite("x.desktop")
    check b.favorites.len == defaultFavorites.len + 1

  test "read-only store never writes":
    let a = newStore("/whisker-nim-test", readOnly = true)
    a.clearRecent()
    a.save()
    check newStore("/whisker-nim-test").recent.len == 2

var
  fileResults: seq[string]
  fileCalls = 0

proc onFiles(data: pointer, paths: seq[string]) =
  fileResults = paths
  inc fileCalls
  gtk_main_quit()

proc giveUp(data: pointer): gboolean {.cdecl.} =
  gtk_main_quit()

suite "filesearch":
  test "finds a file in the home directory through plocate":
    # plocate's index is refreshed periodically, so this looks for a common
    # name instead of a file created by the test. Needs some README under
    # the home directory, outside dot-directories.
    let fs = newFileSearch()
    fs.onResults = onFiles
    fs.request("zzzz-never-reported")
    fs.request("readme") # Replaces the request above.
    let timeout = g_timeout_add(5000, giveUp, nil)
    gtk_main()
    discard g_source_remove(timeout)
    check fileCalls == 1
    check fileResults.len > 0
    check fileResults.len <= fileSearchMaxResults
    for path in fileResults:
      check path.startsWith(getHomeDir())
      check "/." notin path[getHomeDir().len .. ^1]
      check "readme" in path.toLowerAscii()

  test "cancel suppresses the callback":
    let fs = newFileSearch()
    fs.onResults = onFiles
    fileCalls = 0
    fs.request("license")
    fs.cancel()
    let timeout = g_timeout_add(600, giveUp, nil)
    gtk_main()
    check fileCalls == 0
