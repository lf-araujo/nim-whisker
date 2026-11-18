## File search backed by `plocate`, run as a subprocess on the GLib main
## loop so typing never blocks. Each request cancels the one before it.
##
## plocate is asked for file-name matches using its index (fast), and the
## results are narrowed to the home directory and ranked in `filematch`.

import std/[os, strutils]
import ./[config, filematch, glib]

type
  ResultsProc* = proc (data: pointer, paths: seq[string]) {.nimcall.}
  FileSearch* = ref object
    timer: cuint
    process: GSubprocess
    cancellable: GCancellable
    text: string
    onResults*: ResultsProc ## Called with the best matches, possibly none.
    data*: pointer

const plocateLimit = "20000" ## Raw matches read before filtering to home.

proc cancel*(search: FileSearch) =
  ## Drops any pending or running request; its results are never reported.
  if search.timer != 0:
    discard g_source_remove(search.timer)
    search.timer = 0
  if search.process != nil:
    g_cancellable_cancel(search.cancellable)
    g_subprocess_force_exit(search.process)
    g_object_unref(search.cancellable)
    search.cancellable = nil
    search.process = nil # Unreferenced in `onFinished`, which still runs.

proc existing(paths: seq[string], limit: int): seq[string] =
  ## The first `limit` paths still on disk; plocate's index can be stale.
  for path in paths:
    if result.len < limit and (fileExists(path) or dirExists(path)):
      result.add path

proc onFinished(source, res, data: pointer) {.cdecl.} =
  let
    search = cast[FileSearch](data)
    process = cast[GSubprocess](source)
  var output: cstring
  let ok = g_subprocess_communicate_utf8_finish(process, res, addr output,
      nil, nil) != 0
  if process == search.process:
    g_object_unref(search.cancellable)
    search.cancellable = nil
    search.process = nil
    if search.onResults != nil:
      var paths: seq[string]
      if ok and output != nil:
        paths = rankPaths(($output).splitLines(), getHomeDir().strip(
            leading = false, chars = {'/'}), search.text, fileSearchHidden)
      search.onResults(search.data, existing(paths, fileSearchMaxResults))
  g_free(output)
  g_object_unref(process)

proc start(data: pointer): gboolean {.cdecl.} =
  let search = cast[FileSearch](data)
  search.timer = 0
  var args = @["plocate", "-i", "-b", "-l", plocateLimit, "--"]
  args.add queryWords(search.text)
  var argv = newSeq[cstring](args.len + 1)
  for i, arg in args:
    argv[i] = cstring(arg)
  search.process = g_subprocess_newv(addr argv[0],
      G_SUBPROCESS_FLAGS_STDOUT_PIPE or G_SUBPROCESS_FLAGS_STDERR_SILENCE,
      nil)
  if search.process != nil:
    search.cancellable = g_cancellable_new()
    g_subprocess_communicate_utf8_async(search.process, nil,
        search.cancellable, onFinished, data)
  elif search.onResults != nil:
    search.onResults(search.data, @[]) # plocate is not installed.

proc request*(search: FileSearch, text: string) =
  ## Searches for `text` after a short pause in typing. Returns at once;
  ## `onResults` is called later unless another request or `cancel` comes
  ## first. `text` must satisfy `isFileQuery`.
  search.cancel()
  search.text = text
  search.timer = g_timeout_add(fileSearchDelayMs, start,
      cast[pointer](search))

proc newFileSearch*(): FileSearch =
  ## The object must stay alive while a request is pending.
  FileSearch()
