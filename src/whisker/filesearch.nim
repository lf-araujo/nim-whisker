## File search backed by LocalSearch (formerly Tracker), queried over D-Bus
## through libtinysparql on the GLib main loop so typing never blocks. Each
## request cancels the one before it.
##
## A request runs two full-text queries in turn, each limited to one
## LocalSearch graph the way `localsearch search --files` / `--documents`
## are (searching every graph at once is many times slower):
##
## 1. File names (`tracker:FileSystem`), ranked in `filematch` (prefix, word
##    start, shallow path) and reported at once, so results show up while
##    typing. LocalSearch's relevance is not used here: on a file name it
##    mostly rewards short, rare names, which put README files from deep
##    library folders above the user's own.
## 2. File contents (`tracker:Documents`), ordered by LocalSearch's
##    relevance. Their results then replace the first ones: name matches
##    first, with up to `fileSearchContentSlots` rows for content matches.
##    The two are not merged into one ordering, since a long document that
##    mentions a word once would outscore a file named after it.

import std/[os, strutils]
import ./[config, filematch, glib, tinysparql]

type
  ResultsProc* = proc (data: pointer, paths: seq[string],
      final: bool) {.nimcall.}
    ## `final` is false for the quick name-only results and true for the
    ## ones with content matches that follow.
  Step = enum
    stNames, stContents
  Request = ref object
    ## One search. Kept alive (`GC_ref`) while a query is in flight, since
    ## only the C callback holds it then.
    search: FileSearch
    text: string
    step: Step
    cancellable: GCancellable
    statement: TrackerSparqlStatement
    names: seq[string] ## Name matches, from step 1.
  FileSearch* = ref object
    timer: cuint
    current: Request ## The request whose results will be reported.
    text: string
    onResults*: ResultsProc ## Called once or twice, see `ResultsProc`.
    data*: pointer

const
  service = "org.freedesktop.LocalSearch3"
  nameLimit = 5000 ## Raw name matches read before ranking.
  contentLimit = 30

  # `~match` and `~limit` are bound as parameters, never spliced in.
  nameQuery = """
    SELECT ?url WHERE {
      GRAPH tracker:FileSystem {
        ?file a nfo:FileDataObject ; nie:url ?url ; fts:match ~match
      }
    } LIMIT ~limit"""
  contentQuery = """
    SELECT ?url WHERE {
      GRAPH tracker:Documents {
        ?doc a nfo:Document ; nie:isStoredAs ?file ; fts:match ~match
      }
      ?file nie:url ?url
    } ORDER BY DESC(fts:rank(?doc)) LIMIT ~limit"""

var connection: TrackerSparqlConnection
  ## Shared by all searches; opened on first use, retried until it works.

proc localSearch*(): TrackerSparqlConnection =
  ## The shared LocalSearch connection, or nil if it cannot be reached.
  if connection == nil:
    var error: ptr GError
    connection = tracker_sparql_connection_bus_new(service, nil, nil,
        addr error)
    discard takeMessage(error)
  connection

proc accentFold(text: string): string {.nimcall, noSideEffect.} =
  ## Lower case without accents, the way LocalSearch's full-text index
  ## compares words: "Orientações" and "orientacoes" are the same.
  {.cast(noSideEffect).}:
    result = takeString(g_str_to_ascii(cstring(text), nil)).toLowerAscii()

proc homeDir(): string =
  getHomeDir().strip(leading = false, chars = {'/'})

proc existing(paths: seq[string], limit: int): seq[string] =
  ## The first `limit` paths still on disk; the index can lag behind.
  for path in paths:
    if result.len < limit and (fileExists(path) or dirExists(path)):
      result.add path

proc readPaths(cursor: TrackerSparqlCursor): seq[string] =
  ## Reads and frees `cursor`, whose column 0 is a file URI.
  var error: ptr GError
  while tracker_sparql_cursor_next(cursor, nil, addr error) != 0:
    let path = takeString(g_filename_from_uri(
        tracker_sparql_cursor_get_string(cursor, 0, nil), nil, nil))
    if path.len > 0:
      result.add path
  discard takeMessage(error)
  tracker_sparql_cursor_close(cursor)
  g_object_unref(cursor)

proc report(req: Request, paths: seq[string], final: bool) =
  let search = req.search
  if final:
    search.current = nil
  if search.onResults != nil:
    search.onResults(search.data, paths, final)

proc release(req: Request) =
  g_object_unref(req.cancellable)
  GC_unref(req)

proc onCursor(source, res, data: pointer) {.cdecl.}

proc run(req: Request, step: Step): bool =
  ## Starts the query for `step`; false if it could not be started.
  const queries: array[Step, (string, int)] = [
    (nameQuery, nameLimit), (contentQuery, contentLimit)]
  let connection = localSearch()
  if connection == nil:
    return false
  var error: ptr GError
  req.statement = tracker_sparql_connection_query_statement(connection,
      cstring(queries[step][0]), nil, addr error)
  if req.statement == nil:
    discard takeMessage(error)
    return false
  req.step = step
  tracker_sparql_statement_bind_string(req.statement, "match",
      cstring(ftsMatch(req.text)))
  tracker_sparql_statement_bind_int(req.statement, "limit",
      queries[step][1])
  tracker_sparql_statement_execute_async(req.statement, req.cancellable,
      onCursor, cast[pointer](req))
  true

proc onCursor(source, res, data: pointer) {.cdecl.} =
  let req = cast[Request](data)
  var error: ptr GError
  let cursor = tracker_sparql_statement_execute_finish(req.statement, res,
      addr error)
  discard takeMessage(error)
  g_object_unref(req.statement)
  req.statement = nil

  if req.search.current != req: # Cancelled or replaced.
    if cursor != nil:
      tracker_sparql_cursor_close(cursor)
      g_object_unref(cursor)
    req.release()
    return

  let
    found = if cursor != nil: readPaths(cursor) else: @[]
    limit = fileSearchMaxResults
  case req.step
  of stNames:
    req.names = existing(rankPaths(found, homeDir(), req.text,
        fileSearchHidden, accentFold), limit)
    if fileSearchContentSlots > 0 and req.run(stContents):
      req.report(req.names, final = false)
      return
    req.report(req.names, final = true) # No content search.
  of stContents:
    let contents = existing(visiblePaths(found, homeDir(),
        fileSearchHidden), limit + req.names.len)
    req.report(mergeResults(req.names, contents, limit,
        fileSearchContentSlots), final = true)
  req.release()

proc cancel*(search: FileSearch) =
  ## Drops any pending or running request; its results are never reported.
  if search.timer != 0:
    discard g_source_remove(search.timer)
    search.timer = 0
  if search.current != nil:
    g_cancellable_cancel(search.current.cancellable)
    search.current = nil # Released in `onCursor`, which still runs.

proc start(data: pointer): gboolean {.cdecl.} =
  let search = cast[FileSearch](data)
  search.timer = 0
  let req = Request(search: search, text: search.text,
      cancellable: g_cancellable_new())
  GC_ref(req)
  search.current = req
  if ftsMatch(req.text).len == 0 or not req.run(stNames):
    req.report(@[], final = true) # Nothing to search, or no LocalSearch.
    req.release()

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
