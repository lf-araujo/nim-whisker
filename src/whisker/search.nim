## Incremental search over launchers, search actions and the run action.
## Ported from upstream `search-page.cpp`.

import std/[algorithm, sequtils, strutils]
import ./[config, elements, query]

type
  Match = object
    element: Element
    relevancy: uint32
  Search* = ref object
    actions: seq[Element]
    runAction: Element
    launchers: seq[Element] ## Search order: recent, favorites, then by name.
    query: Query
    matches: seq[Match]

proc byRelevancy(a, b: Match): int = cmp(a.relevancy, b.relevancy)

proc newSearch*(): Search =
  result = Search(runAction: newRunAction())
  for spec in searchActions:
    result.actions.add newSearchAction(spec)

proc clear*(search: Search) =
  ## Forgets the current query and its results.
  search.query = Query()
  search.matches.setLen(0)

func text*(search: Search): string =
  ## The query the current results are for; empty when there is none.
  search.query.raw

proc setLaunchers*(search: Search, launchers: seq[Element]) =
  ## Replaces the searched launchers, given in the order ties should keep.
  search.clear()
  search.launchers = launchers

proc update*(search: Search, text: string, noResults: var bool): seq[Element] =
  ## Returns the results for the non-empty query `text`, best first. When
  ## nothing matches, `noResults` is set and every prefix search action is
  ## offered for the text instead.
  noResults = false
  # Narrow the previous results when the query was only extended.
  if search.query.isEmpty or not text.startsWith(search.query.raw):
    search.matches = @[Match(element: search.runAction)]
    for launcher in search.launchers:
      search.matches.add Match(element: launcher)
  elif not search.matches.anyIt(it.element == search.runAction):
    search.matches.insert(Match(element: search.runAction), 0)
  search.query = newQuery(text)

  var actionMatches: seq[Match]
  for action in search.actions:
    let relevancy = action.search(search.query)
    if relevancy != noMatch:
      actionMatches.add Match(element: action, relevancy: relevancy)
  actionMatches.sort(byRelevancy)
  actionMatches.reverse()

  for match in search.matches.mitems:
    match.relevancy = match.element.search(search.query)
  search.matches.keepItIf(it.relevancy != noMatch)
  search.matches.sort(byRelevancy)

  if actionMatches.len == 0 and search.matches.len == 0:
    noResults = true
    for action in search.actions:
      if not action.isRegex:
        discard action.search(newQuery(action.pattern & text))
        actionMatches.add Match(element: action)

  for match in actionMatches:
    result.add match.element
  for match in search.matches:
    result.add match.element
