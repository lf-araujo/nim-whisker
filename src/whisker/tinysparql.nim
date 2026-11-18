## Minimal hand-written bindings for TinySPARQL (libtinysparql-3.0), the
## query library of LocalSearch (formerly Tracker).
##
## Only what the file search uses is declared. Procs keep their C names, as
## in `glib.nim`. No C headers are needed: every type is opaque.

import ./glib

{.passL: "-l:libtinysparql-3.0.so.0".}

type
  TrackerSparqlConnection* = ptr object
  TrackerSparqlStatement* = ptr object
  TrackerSparqlCursor* = ptr object

{.push importc, cdecl.}
proc tracker_sparql_connection_bus_new*(serviceName, objectPath: cstring,
    dbusConnection: pointer, error: ptr ptr GError): TrackerSparqlConnection
proc tracker_sparql_connection_query_statement*(
    connection: TrackerSparqlConnection, sparql: cstring,
    cancellable: GCancellable, error: ptr ptr GError): TrackerSparqlStatement
proc tracker_sparql_statement_bind_string*(statement: TrackerSparqlStatement,
    name, value: cstring)
proc tracker_sparql_statement_bind_int*(statement: TrackerSparqlStatement,
    name: cstring, value: int64)
proc tracker_sparql_statement_execute_async*(
    statement: TrackerSparqlStatement, cancellable: GCancellable,
    callback: GAsyncReadyCallback, data: pointer)
proc tracker_sparql_statement_execute_finish*(
    statement: TrackerSparqlStatement, res: pointer,
    error: ptr ptr GError): TrackerSparqlCursor
proc tracker_sparql_cursor_next*(cursor: TrackerSparqlCursor,
    cancellable: GCancellable, error: ptr ptr GError): gboolean
proc tracker_sparql_cursor_get_string*(cursor: TrackerSparqlCursor,
    column: cint, length: ptr clong): cstring ## Borrowed; do not free.
proc tracker_sparql_cursor_close*(cursor: TrackerSparqlCursor)
{.pop.}
