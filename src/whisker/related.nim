## Files related to a file, for the actions panel, found the way Synapse
## did plus a content search. Asynchronous on the GLib main loop:
##
## 1. *Used together*: Zeitgeist's `FindRelatedUris`, files the user had
##    open in the same sessions as this one (Zeitgeist logs what apps open,
##    fed by GTK's recent-files list).
## 2. *Similar*: LocalSearch documents whose text matches a few words of
##    this file's title, by relevance. The title is the front-matter title
##    of a text file (a Better Notes note names its paper there), else the
##    document title LocalSearch extracted, else the file name.
##
## Either source may be missing; the other still answers.

import std/[os, strutils, times]
import ./[config, filematch, filesearch, glib, relatedmatch, tinysparql]

type
  RelatedFile* = tuple[path, reason: string]
  RelatedProc* = proc (data: pointer, token: int,
      related: seq[RelatedFile]) {.nimcall.}
  Step = enum
    stUsed, stTitle, stSimilar, stSimilarFewer
  Lookup = ref object
    ## One lookup; kept alive (`GC_ref`) while a call is in flight.
    path, uri: string
    token: int
    onDone: RelatedProc
    data: pointer
    step: Step
    statement: TrackerSparqlStatement
    title: string
    used: seq[string]

const
  zeitgeistLimit = 12
  similarLimit = 15
  titleQuery = """
    SELECT ?title WHERE {
      GRAPH tracker:FileSystem { ?file nie:url ~url }
      GRAPH tracker:Documents { ?doc nie:isStoredAs ?file ; nie:title ?title }
    } LIMIT 1"""
  similarQuery = """
    SELECT ?url WHERE {
      GRAPH tracker:Documents {
        ?doc a nfo:Document ; nie:isStoredAs ?file ; fts:match ~match
      }
      ?file nie:url ?url
    } ORDER BY DESC(fts:rank(?doc)) LIMIT ~limit"""

var zeitgeist: GDBusProxy ## Opened on first use; nil while unreachable.

proc zeitgeistLog(): GDBusProxy =
  if zeitgeist == nil:
    const doNotLoadProperties = 1'i32
    const doNotConnectSignals = 2'i32
    var error: ptr GError
    zeitgeist = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SESSION,
        doNotLoadProperties or doNotConnectSignals, nil,
        "org.gnome.zeitgeist.Engine", "/org/gnome/zeitgeist/log/activity",
        "org.gnome.zeitgeist.Log", nil, addr error)
    discard takeMessage(error)
  zeitgeist

proc home(): string =
  getHomeDir().strip(leading = false, chars = {'/'})

proc usable(lookup: Lookup, paths: seq[string]): seq[string] =
  ## Visible files under home that exist, other than the file itself.
  for path in visiblePaths(paths, home(), fileSearchHidden):
    if path != lookup.path and (fileExists(path) or dirExists(path)):
      result.add path

proc finish(lookup: Lookup, similar: seq[string]) =
  var related: seq[RelatedFile]
  for path in mergeResults(lookup.used, similar, relatedMaxResults,
      relatedSimilarSlots):
    related.add (path, if path in lookup.used: "used together" else: "similar")
  lookup.onDone(lookup.data, lookup.token, related)
  GC_unref(lookup)

# --- Zeitgeist ----------------------------------------------------------------

proc eventTemplate(subjectUri: string): GVariant =
  ## A Zeitgeist event template `(as, aas, ay)` matching any event whose
  ## subject URI is `subjectUri` ("file://*" matches every file).
  var
    eventFields: array[6, cstring] # id, timestamp, interpretation, ...
    subjectFields: array[9, cstring] # uri, interpretation, ...
  for field in eventFields.mitems: field = ""
  for field in subjectFields.mitems: field = ""
  subjectFields[0] = cstring(subjectUri)
  var subject = g_variant_new_strv(addr subjectFields[0], subjectFields.len)
  g_variant_new("(@as@aas@ay)",
      g_variant_new_strv(addr eventFields[0], eventFields.len),
      g_variant_new_array(nil, addr subject, 1),
      g_variant_new_array("y", nil, 0))

proc onTitleStep(lookup: Lookup)

proc onZeitgeist(source, res, data: pointer) {.cdecl.} =
  let lookup = cast[Lookup](data)
  var error: ptr GError
  let reply = g_dbus_proxy_call_finish(cast[GDBusProxy](source), res,
      addr error)
  discard takeMessage(error)
  if reply != nil:
    let uris = g_variant_get_child_value(reply, 0)
    var count: csize_t
    let strv = g_variant_get_strv(uris, addr count)
    var paths: seq[string]
    for i in 0 ..< int(count):
      let path = takeString(g_filename_from_uri(strv[i], nil, nil))
      if path.len > 0:
        paths.add path
    g_free(strv)
    g_variant_unref(uris)
    g_variant_unref(reply)
    lookup.used = lookup.usable(paths)
  lookup.onTitleStep()

proc askZeitgeist(lookup: Lookup): bool =
  let log = zeitgeistLog()
  if log == nil:
    return false
  var
    query = eventTemplate(lookup.uri)
    results = eventTemplate("file://*")
  const
    anyStorage = 2'u32
    mostRecent = 0'u32 # Same order as "most related" on this history.
  let params = g_variant_new("((xx)@a(asaasay)@a(asaasay)uuu)",
      0'i64, int64(epochTime() * 1000),
      g_variant_new_array(nil, addr query, 1),
      g_variant_new_array(nil, addr results, 1),
      anyStorage, uint32(zeitgeistLimit), mostRecent)
  g_dbus_proxy_call(log, "FindRelatedUris", params, 0, 5000, nil,
      onZeitgeist, cast[pointer](lookup))
  true

# --- LocalSearch ----------------------------------------------------------------

proc onCursor(source, res, data: pointer) {.cdecl.}

proc run(lookup: Lookup, step: Step, sparql: string,
    bindings: openArray[(string, string)], limit = 0): bool =
  let connection = localSearch()
  if connection == nil:
    return false
  var error: ptr GError
  lookup.statement = tracker_sparql_connection_query_statement(connection,
      cstring(sparql), nil, addr error)
  if lookup.statement == nil:
    discard takeMessage(error)
    return false
  lookup.step = step
  for (name, value) in bindings:
    tracker_sparql_statement_bind_string(lookup.statement, cstring(name),
        cstring(value))
  if limit > 0:
    tracker_sparql_statement_bind_int(lookup.statement, "limit", limit)
  tracker_sparql_statement_execute_async(lookup.statement, nil, onCursor,
      cast[pointer](lookup))
  true

proc searchSimilar(lookup: Lookup, step: Step) =
  let
    count = if step == stSimilar: 5 else: 3
    words = keyWords(lookup.title, count)
  if words.len == 0 or not lookup.run(step, similarQuery,
      [("match", ftsMatch(words.join(" ")))], similarLimit):
    lookup.finish(@[])

proc onTitleStep(lookup: Lookup) =
  ## Picks the title to search with: front matter, then LocalSearch's.
  if lookup.path.splitFile.ext.toLowerAscii() in
      [".md", ".markdown", ".org", ".txt"]:
    try:
      let f = open(lookup.path)
      defer: f.close()
      var head = newString(4096)
      head.setLen(f.readBuffer(addr head[0], head.len))
      lookup.title = frontMatterTitle(head)
    except IOError, OSError:
      discard
  if lookup.title.len > 0:
    lookup.searchSimilar(stSimilar)
  elif not lookup.run(stTitle, titleQuery, [("url", lookup.uri)]):
    lookup.title = fileNameTitle(lookup.path)
    lookup.searchSimilar(stSimilar)

proc onCursor(source, res, data: pointer) {.cdecl.} =
  let lookup = cast[Lookup](data)
  var error: ptr GError
  let cursor = tracker_sparql_statement_execute_finish(lookup.statement, res,
      addr error)
  discard takeMessage(error)
  g_object_unref(lookup.statement)
  lookup.statement = nil
  var values: seq[string]
  if cursor != nil:
    while tracker_sparql_cursor_next(cursor, nil, addr error) != 0:
      values.add toStr(tracker_sparql_cursor_get_string(cursor, 0, nil))
    discard takeMessage(error)
    tracker_sparql_cursor_close(cursor)
    g_object_unref(cursor)

  case lookup.step
  of stTitle:
    let title = if values.len > 0: values[0] else: ""
    lookup.title =
      if isUsefulTitle(title): title else: fileNameTitle(lookup.path)
    lookup.searchSimilar(stSimilar)
  of stSimilar, stSimilarFewer:
    var paths: seq[string]
    for uri in values:
      let path = takeString(g_filename_from_uri(cstring(uri), nil, nil))
      if path.len > 0:
        paths.add path
    let similar = lookup.usable(paths)
    # All five words can be too strict for a short or unusual title.
    if similar.len < 2 and lookup.step == stSimilar and
        keyWords(lookup.title, 5).len > 3:
      lookup.searchSimilar(stSimilarFewer)
    else:
      lookup.finish(similar)
  of stUsed:
    discard # Zeitgeist answers through `onZeitgeist`.

proc findRelated*(path: string, token: int, onDone: RelatedProc,
    data: pointer) =
  ## Looks up the files related to `path`; `onDone` is called once, later,
  ## with `token` and the results (possibly none).
  let file = g_file_new_for_path(cstring(path))
  let lookup = Lookup(path: path, uri: takeString(g_file_get_uri(file)),
      token: token, onDone: onDone, data: data)
  g_object_unref(file)
  GC_ref(lookup)
  if not lookup.askZeitgeist():
    lookup.onTitleStep()
