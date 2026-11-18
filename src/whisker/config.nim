## Compile-time configuration.
##
## There is no settings dialog yet. These constants are a snapshot of the
## Whisker Menu configuration this rewrite was started against (xfconf
## channel `xfce4-panel`, 2026-11-15); anything not listed there keeps
## upstream's default. Edit and rebuild to change the look.

type
  DefaultCategory* = enum
    dcFavorites, dcRecent, dcAll
  SearchActionSpec* = object
    name*, pattern*, command*: string
    isRegex*: bool
  CommandSpec* = object
    icon*, fallbackIcon*: string
    text*: string ## Mnemonic label; `_` marks the accelerator.
    command*: string
    shown*: bool
    errorText*: string
    confirmQuestion*, confirmStatus*: string ## Both empty: no confirmation.

const
  # Panel button
  buttonTitle* = "Menu"
  buttonIcon* = "start-here-solus-mono"
  buttonTitleVisible* = true
  buttonIconVisible* = true
  buttonSingleRow* = false

  # Menu window: icon view, categories as an icon-only row on top, search
  # entry with the session commands beside it, no profile picture.
  menuWidth* = 450
  menuHeight* = 500
  menuOpacity* = 46 ## Percent; applies to the window background only.
  launcherIconSize* = 64 ## Upstream "Large" (launcher-icon-size 4).
  launcherItemPadding* = 4 ## Upstream's padding for Small..Large icons.
  categoryIconSize* = 32 ## Upstream "Small" (category-icon-size 2).
  launcherShowTooltip* = false
  defaultCategory* = dcRecent
  sortCategories* = true

  # Behaviour
  recentItemsMax* = 40
  favoritesInRecent* = true
  stayOnFocusOut* = false
  confirmSessionCommand* = true

  # Search results: the application grid, then a "Settings" list, then a
  # "Files" list. The lists take the height they need, so their sizes
  # decide how much of the menu is left for the grid.
  searchMaxApps* = 0 ## Application matches shown; 0 shows them all.
  searchMaxSettings* = 3
  searchGridMinHeight* = 120 ## Keeps one row of launchers visible.

  # File search: results appear under the applications while typing.
  # Backed by LocalSearch (Tracker), limited to the home directory. Matches
  # file names and, through LocalSearch's full-text index, file contents.
  fileSearchEnabled* = true
  fileSearchMinChars* = 3
  fileSearchMaxResults* = 5
  fileSearchContentSlots* = 2 ## Rows kept for content matches; 0 turns
                              ## content search off.
  fileSearchHidden* = false ## Include dot-files and files in dot-directories.
  fileSearchDelayMs* = 150 ## Pause in typing before LocalSearch is asked.

  # "Related" section of a file's actions: files used in the same sessions
  # (Zeitgeist), then files with similar content (LocalSearch).
  relatedMaxResults* = 6
  relatedSimilarSlots* = 3 ## Rows kept for similar files; unused rows go
                           ## to the other kind.

  defaultFavorites* = [
    "xfce4-web-browser.desktop",
    "xfce4-mail-reader.desktop",
    "xfce4-file-manager.desktop",
    "xfce4-terminal-emulator.desktop"]

  searchActions* = [
    SearchActionSpec(name: "Man Pages", pattern: "#",
      command: "exo-open --launch TerminalEmulator man %s"),
    SearchActionSpec(name: "Search the Web", pattern: "?",
      command: "exo-open --launch WebBrowser https://duckduckgo.com/?q=%u"),
    SearchActionSpec(name: "Search for Files", pattern: "!sf",
      command: "catfish --path=~ --start %s"),
    SearchActionSpec(name: "Wikipedia", pattern: "!w",
      command: "exo-open --launch WebBrowser https://en.wikipedia.org/wiki/%u"),
    SearchActionSpec(name: "Run in Terminal", pattern: "!",
      command: "exo-open --launch TerminalEmulator %s"),
    SearchActionSpec(name: "Open URI",
      pattern: "^(file|http|https):\\/\\/(.*)$", command: "exo-open \\0",
      isRegex: true),
    SearchActionSpec(name: "Pubmed", pattern: "!pubmed",
      command: "exo-open --launch WebBrowser  https://pubmed.ncbi.nlm.nih.gov/?term=%u"),
    SearchActionSpec(name: "Search Tracker", pattern: "-",
      command: "exo-open --launch TerminalEmulator  lsfz %s"),
    SearchActionSpec(name: "Quick run command", pattern: "!r",
      command: "exo-open --launch  %s")]

  # The nine buttons beside the search entry, in upstream's order.
  sessionCommands* = [
    CommandSpec(icon: "org.xfce.settings.manager",
      fallbackIcon: "preferences-desktop", text: "_Settings Manager",
      command: "xfce4-settings-manager", shown: true,
      errorText: "Failed to open settings manager."),
    CommandSpec(icon: "xfsm-lock", fallbackIcon: "system-lock-screen",
      text: "_Lock Screen", command: "xflock4", shown: true,
      errorText: "Failed to lock screen."),
    CommandSpec(icon: "xfsm-switch-user", fallbackIcon: "system-users",
      text: "Switch _User", command: "xfce4-session-logout --switch-user",
      shown: false, errorText: "Failed to switch user."),
    CommandSpec(icon: "xfsm-logout", fallbackIcon: "system-log-out",
      text: "Log _Out", command: "xfce4-session-logout --logout --fast",
      shown: false, errorText: "Failed to log out.",
      confirmQuestion: "Are you sure you want to log out?",
      confirmStatus: "Logging out in %d seconds."),
    CommandSpec(icon: "xfsm-reboot", fallbackIcon: "system-reboot",
      text: "_Restart", command: "xfce4-session-logout --reboot --fast",
      shown: false, errorText: "Failed to restart.",
      confirmQuestion: "Are you sure you want to restart?",
      confirmStatus: "Restarting computer in %d seconds."),
    CommandSpec(icon: "xfsm-shutdown", fallbackIcon: "system-shutdown",
      text: "Shut _Down", command: "xfce4-session-logout --halt --fast",
      shown: true, errorText: "Failed to shut down.",
      confirmQuestion: "Are you sure you want to shut down?",
      confirmStatus: "Turning off computer in %d seconds."),
    CommandSpec(icon: "xfsm-suspend", fallbackIcon: "system-suspend",
      text: "Suspe_nd", command: "xfce4-session-logout --suspend",
      shown: false, errorText: "Failed to suspend.",
      confirmQuestion: "Do you want to suspend to RAM?",
      confirmStatus: "Suspending computer in %d seconds."),
    CommandSpec(icon: "xfsm-hibernate", fallbackIcon: "system-hibernate",
      text: "_Hibernate", command: "xfce4-session-logout --hibernate",
      shown: true, errorText: "Failed to hibernate.",
      confirmQuestion: "Do you want to suspend to disk?",
      confirmStatus: "Hibernating computer in %d seconds."),
    CommandSpec(icon: "xfsm-logout", fallbackIcon: "system-log-out",
      text: "Log Ou_t...", command: "xfce4-session-logout", shown: true,
      errorText: "Failed to log out.")]
