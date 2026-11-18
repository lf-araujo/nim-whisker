## Session command buttons (settings, lock, shut down, ...) and their
## confirmation dialog. Ported from upstream `command.cpp`.

import std/strutils
import ./[config, glib, gtk, xfce]

type
  Countdown = object
    dialog: GtkWidget
    status: cstring
    timeLeft: cint

const indexKey = "whisker-command"

proc isValid(spec: CommandSpec): bool =
  ## Whether the command's program is in `PATH`.
  var argv: ptr cstring
  if g_shell_parse_argv(cstring(spec.command), nil, addr argv, nil) != 0:
    let path = g_find_program_in_path(
        cast[ptr UncheckedArray[cstring]](argv)[0])
    result = path != nil
    g_free(path)
    g_strfreev(argv)

proc iconName(spec: CommandSpec): string =
  if gtk_icon_theme_has_icon(gtk_icon_theme_get_default(),
      cstring(spec.icon)) != 0:
    spec.icon
  else:
    spec.fallbackIcon

proc tick(data: pointer): gboolean {.cdecl.} =
  let countdown = cast[ptr Countdown](data)
  if countdown.timeLeft == 0:
    gtk_dialog_response(countdown.dialog, GTK_RESPONSE_ACCEPT)
  else:
    gtk_message_dialog_format_secondary_text(countdown.dialog,
        countdown.status, countdown.timeLeft)
  dec countdown.timeLeft
  gboolean(countdown.timeLeft >= 0)

proc confirm(spec: CommandSpec): bool =
  ## Asks before a session command. As upstream, the command goes ahead on
  ## its own when the 60 second countdown runs out.
  let
    icon = iconName(spec)
    dialog = gtk_message_dialog_new(nil, 0, GTK_MESSAGE_QUESTION,
        GTK_BUTTONS_CANCEL, "%s", cstring(spec.confirmQuestion))
    header = gtk_header_bar_new()
  gtk_window_set_deletable(dialog, 0)
  gtk_window_set_keep_above(dialog, 1)
  gtk_window_set_skip_taskbar_hint(dialog, 1)
  gtk_window_stick(dialog)
  gtk_header_bar_set_has_subtitle(header, 0)
  gtk_header_bar_set_show_close_button(header, 0)
  gtk_widget_show(header)
  gtk_window_set_titlebar(dialog, header)

  let image = gtk_image_new_from_icon_name(cstring(icon),
      GTK_ICON_SIZE_DIALOG)
  gtk_widget_show(image)
  gtk_message_dialog_set_image(dialog, image)
  let button = gtk_dialog_add_button(dialog, cstring(spec.text),
      GTK_RESPONSE_ACCEPT)
  gtk_button_set_image(button, gtk_image_new_from_icon_name(cstring(icon),
      GTK_ICON_SIZE_BUTTON))
  gtk_dialog_set_default_response(dialog, GTK_RESPONSE_ACCEPT)

  var countdown = Countdown(dialog: dialog,
      status: cstring(spec.confirmStatus), timeLeft: 60)
  let timeout = g_timeout_add(1000, tick, addr countdown)
  discard tick(addr countdown)
  result = gtk_dialog_run(dialog) == GTK_RESPONSE_ACCEPT
  discard g_source_remove(timeout)
  gtk_widget_destroy(dialog)

proc activate(spec: CommandSpec) =
  let needsConfirm = confirmSessionCommand and
      spec.confirmQuestion.len > 0 and spec.confirmStatus.len > 0
  if not needsConfirm or confirm(spec):
    var error: ptr GError
    if g_spawn_command_line_async(cstring(spec.command), addr error) == 0:
      xfce_dialog_show_error(nil, error, "%s", cstring(spec.errorText))
      g_error_free(error)

proc onClicked(button: GtkWidget, data: pointer) {.cdecl.} =
  let index = cast[int](g_object_get_data(button, indexKey))
  activate(sessionCommands[index])

proc newCommandButton*(index: int): GtkWidget =
  ## Creates the button for `config.sessionCommands[index]`. Connect your own
  ## "clicked" handler first to close the menu; the command itself runs in
  ## an "after" handler.
  let spec = sessionCommands[index]
  result = gtk_button_new()
  gtk_button_set_relief(result, GTK_RELIEF_NONE)
  gtk_widget_set_tooltip_text(result, cstring(spec.text.replace("_", "")))
  gtk_container_add(result, gtk_image_new_from_icon_name(
      cstring(iconName(spec)), GTK_ICON_SIZE_LARGE_TOOLBAR))
  result.addClass("command-button")
  g_object_set_data(result, indexKey, cast[pointer](index))
  g_signal_connect_after(result, "clicked", cast[GCallback](onClicked))

proc refreshCommandButton*(button: GtkWidget) =
  ## Shows the button if its command is enabled; greys it out if the
  ## program is missing.
  let spec = sessionCommands[cast[int](g_object_get_data(button, indexKey))]
  if spec.shown:
    gtk_widget_show_all(button)
  else:
    gtk_widget_hide(button)
  gtk_widget_set_sensitive(button, gboolean(isValid(spec)))
