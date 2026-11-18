## Minimal hand-written bindings for GLib, GObject and GIO.
##
## Only what whisker-nim uses is declared. Procs keep their C names so the
## code can be read side by side with upstream Whisker Menu and the GLib
## documentation. No C headers are needed: every type is opaque or declared
## here with its stable ABI layout.

{.passL: "-l:libglib-2.0.so.0 -l:libgobject-2.0.so.0 -l:libgio-2.0.so.0".}

type
  gboolean* = cint
  GType* = csize_t
  GObject* = ptr object
  GIcon* = ptr object
  GFile* = ptr object
  GAppInfo* = ptr object
  GVariant* = ptr object
  GDBusProxy* = ptr object
  GSubprocess* = ptr object
  GCancellable* = ptr object
  GAsyncReadyCallback* = proc (source, res, data: pointer) {.cdecl.}
  GRegex* = ptr object
  GMatchInfo* = ptr object
  GCallback* = pointer
  GSourceFunc* = proc (data: pointer): gboolean {.cdecl.}
  GError* = object
    domain*: uint32
    code*: cint
    message*: cstring
  GList* = object
    data*: pointer
    next*, prev*: ptr GList
  GTypeQuery* = object
    gtype*: GType
    typeName*: cstring
    classSize*, instanceSize*: cuint
  GTypeInfo* = object
    classSize*: uint16
    baseInit*, baseFinalize*: pointer
    classInit*: proc (klass, classData: pointer) {.cdecl.}
    classFinalize*: pointer
    classData*: pointer
    instanceSize*: uint16
    nPreallocs*: uint16
    instanceInit*: pointer
    valueTable*: pointer

const
  G_TYPE_BOOLEAN* = GType(5 shl 2)
  G_TYPE_INT* = GType(6 shl 2)
  G_TYPE_STRING* = GType(16 shl 2)
  G_TYPE_POINTER* = GType(17 shl 2)
  G_SPAWN_SEARCH_PATH* = cint(1 shl 2)
  G_NORMALIZE_DEFAULT* = cint(0)
  G_REGEX_OPTIMIZE* = cint(1 shl 1)
  G_CONNECT_AFTER* = cint(1)
  G_BUS_TYPE_SESSION* = cint(2)
  G_USER_DIRECTORY_DESKTOP* = cint(0)
  G_FILE_COPY_NONE* = cint(0)
  G_SUBPROCESS_FLAGS_STDOUT_PIPE* = cint(1 shl 2)
  G_SUBPROCESS_FLAGS_STDERR_SILENCE* = cint(1 shl 5)

{.push importc, cdecl.}
proc g_free*(mem: pointer)
proc g_strfreev*(strv: ptr cstring)
proc g_error_free*(error: ptr GError)
proc g_list_free*(list: ptr GList)
proc g_list_append*(list: ptr GList, data: pointer): ptr GList
proc g_strdup*(str: cstring): cstring
proc g_icon_to_string*(icon: GIcon): cstring
proc g_icon_new_for_string*(str: cstring, error: ptr ptr GError): GIcon
proc g_object_set_data_full*(obj: pointer, key: cstring, data: pointer,
    destroy: pointer)
proc g_app_info_get_all_for_type*(contentType: cstring): ptr GList
proc g_app_info_should_show*(info: GAppInfo): gboolean
proc g_app_info_get_display_name*(info: GAppInfo): cstring
proc g_app_info_get_icon*(info: GAppInfo): GIcon
proc g_app_info_launch_uris*(info: GAppInfo, uris: ptr GList, context: pointer,
    error: ptr ptr GError): gboolean
proc g_file_trash*(file: GFile, cancellable: pointer,
    error: ptr ptr GError): gboolean

proc g_utf8_normalize*(str: cstring, len: int, mode: cint): cstring
proc g_utf8_casefold*(str: cstring, len: int): cstring
proc g_utf8_collate_key*(str: cstring, len: int): cstring
proc g_utf8_validate*(str: cstring, maxLen: int, endp: ptr cstring): gboolean
proc g_markup_escape_text*(text: cstring, len: int): cstring
proc g_uri_escape_string*(unescaped, reservedAllowed: cstring,
    allowUtf8: gboolean): cstring
proc g_path_is_absolute*(fileName: cstring): gboolean
proc g_filename_from_uri*(uri: cstring, hostname: ptr cstring,
    error: ptr ptr GError): cstring
proc g_str_to_ascii*(str, fromLocale: cstring): cstring

proc g_shell_parse_argv*(commandLine: cstring, argc: ptr cint,
    argv: ptr ptr cstring, error: ptr ptr GError): gboolean
proc g_find_program_in_path*(program: cstring): cstring
proc g_spawn_command_line_async*(commandLine: cstring,
    error: ptr ptr GError): gboolean
proc g_get_user_special_dir*(directory: cint): cstring
proc g_get_monotonic_time*(): int64
proc g_chmod*(path: cstring, mode: cint): cint {.importc: "chmod".}

proc g_idle_add*(function: GSourceFunc, data: pointer): cuint
proc g_timeout_add*(interval: cuint, function: GSourceFunc,
    data: pointer): cuint
proc g_source_remove*(tag: cuint): gboolean

proc g_regex_new*(pattern: cstring, compileOptions, matchOptions: cint,
    error: ptr ptr GError): GRegex
proc g_regex_match*(regex: GRegex, str: cstring, matchOptions: cint,
    matchInfo: ptr GMatchInfo): gboolean
proc g_match_info_expand_references*(matchInfo: GMatchInfo, str: cstring,
    error: ptr ptr GError): cstring
proc g_match_info_free*(matchInfo: GMatchInfo)

proc g_object_ref*(obj: pointer): pointer
proc g_object_ref_sink*(obj: pointer): pointer
proc g_object_unref*(obj: pointer)
proc g_object_new*(gtype: GType, firstProperty: cstring): pointer {.varargs.}
proc g_object_set*(obj: pointer, firstProperty: cstring) {.varargs.}
proc g_object_set_data*(obj: pointer, key: cstring, data: pointer)
proc g_object_get_data*(obj: pointer, key: cstring): pointer
proc g_signal_connect_data*(instance: pointer, detailedSignal: cstring,
    handler: GCallback, data: pointer, destroyData: pointer,
    connectFlags: cint): culong
proc g_signal_handlers_disconnect_matched*(instance: pointer, mask: cint,
    signalId: cuint, detail: uint32, closure, function, data: pointer): cuint
proc g_type_query*(gtype: GType, query: ptr GTypeQuery)
proc g_type_register_static*(parent: GType, name: cstring,
    info: ptr GTypeInfo, flags: cint): GType
proc g_type_from_name*(name: cstring): GType
proc g_type_check_instance_is_a*(instance: pointer, gtype: GType): gboolean

proc g_icon_get_type*(): GType
proc g_themed_icon_new*(iconName: cstring): GIcon
proc g_file_icon_new*(file: GFile): GIcon
proc g_file_new_for_path*(path: cstring): GFile
proc g_file_get_basename*(file: GFile): cstring
proc g_file_get_child*(file: GFile, name: cstring): GFile
proc g_file_get_path*(file: GFile): cstring
proc g_file_get_uri*(file: GFile): cstring
proc g_file_copy*(source, destination: GFile, flags: cint,
    cancellable, progressCallback, progressData: pointer,
    error: ptr ptr GError): gboolean

proc g_file_get_parent*(file: GFile): GFile
proc g_content_type_guess*(filename: cstring, data: pointer, dataSize: csize_t,
    resultUncertain: ptr gboolean): cstring
proc g_content_type_get_icon*(contentType: cstring): GIcon
proc g_app_info_launch_default_for_uri*(uri: cstring, context: pointer,
    error: ptr ptr GError): gboolean

proc g_cancellable_new*(): GCancellable
proc g_cancellable_cancel*(cancellable: GCancellable)
proc g_subprocess_newv*(argv: ptr cstring, flags: cint,
    error: ptr ptr GError): GSubprocess
proc g_subprocess_force_exit*(subprocess: GSubprocess)
proc g_subprocess_communicate_utf8_async*(subprocess: GSubprocess,
    stdinBuf: cstring, cancellable: GCancellable,
    callback: GAsyncReadyCallback, data: pointer)
proc g_subprocess_communicate_utf8_finish*(subprocess: GSubprocess,
    res: pointer, stdoutBuf, stderrBuf: ptr cstring,
    error: ptr ptr GError): gboolean

proc g_variant_new*(format: cstring): GVariant {.varargs.}
proc g_variant_unref*(value: GVariant)
proc g_variant_new_strv*(strv: ptr cstring, length: int): GVariant
proc g_variant_new_array*(childType: cstring, children: ptr GVariant,
    nChildren: csize_t): GVariant
  ## `childType` is a type string such as "y" (G_VARIANT_TYPE is a cast).
proc g_variant_get_child_value*(value: GVariant, index: csize_t): GVariant
proc g_variant_get_strv*(value: GVariant,
    length: ptr csize_t): ptr UncheckedArray[cstring]
  ## Free the array (not its strings) with `g_free`.
proc g_dbus_proxy_call*(proxy: GDBusProxy, methodName: cstring,
    parameters: GVariant, flags, timeoutMsec: cint, cancellable: pointer,
    callback: GAsyncReadyCallback, data: pointer)
proc g_dbus_proxy_call_finish*(proxy: GDBusProxy, res: pointer,
    error: ptr ptr GError): GVariant
proc g_dbus_proxy_new_for_bus_sync*(busType, flags: cint, info: pointer,
    name, objectPath, interfaceName: cstring, cancellable: pointer,
    error: ptr ptr GError): GDBusProxy
proc g_dbus_proxy_call_sync*(proxy: GDBusProxy, methodName: cstring,
    parameters: GVariant, flags, timeoutMsec: cint, cancellable: pointer,
    error: ptr ptr GError): GVariant
{.pop.}

proc g_signal_connect*(instance: pointer, signal: cstring, handler: GCallback,
    data: pointer = nil): culong {.discardable.} =
  g_signal_connect_data(instance, signal, handler, data, nil, 0)

proc g_signal_connect_after*(instance: pointer, signal: cstring,
    handler: GCallback, data: pointer = nil): culong {.discardable.} =
  g_signal_connect_data(instance, signal, handler, data, nil, G_CONNECT_AFTER)

proc takeString*(str: cstring): string =
  ## Copies a GLib-allocated string into a Nim string and frees the original.
  if str != nil:
    result = $str
    g_free(str)

proc toStr*(str: cstring): string =
  ## Copies a borrowed C string; `nil` becomes the empty string.
  if str != nil:
    result = $str

proc takeMessage*(error: ptr GError): string =
  ## Returns the message of `error` and frees it.
  if error != nil:
    result = toStr(error.message)
    g_error_free(error)
