## Filtering and ranking of file search candidates. Pure Nim, no GTK.

import std/[algorithm, strutils]

func isFileQuery*(text: string, minChars: int): bool =
  ## Whether `text` should be searched for as a file name. Short queries and
  ## ones that look like a search action (`!w foo`, `?foo`) or a URI are not.
  let query = text.strip()
  query.len >= minChars and query[0] notin {'!', '?', '#', '-'} and
    "://" notin query

func queryWords*(text: string): seq[string] =
  ## The lower-cased words every result's file name must contain.
  strutils.splitWhitespace(text.toLowerAscii())

func baseName(path: string): string =
  path[path.rfind('/') + 1 .. ^1]

func isCandidate(path, home: string, words: seq[string],
    includeHidden: bool): bool =
  if not path.startsWith(home & "/"):
    return false
  if not includeHidden and "/." in path[home.len .. ^1]:
    return false
  let name = baseName(path).toLowerAscii()
  for word in words:
    if word notin name:
      return false
  true

func score(path: string, words: seq[string]): tuple[match, depth, len: int] =
  ## Lower is better: name starts with the query, then a word of the name
  ## does, then any substring; shallower and shorter paths break ties.
  let name = baseName(path).toLowerAscii()
  var match = 2
  if name.startsWith(words[0]):
    match = 0
  else:
    let pos = name.find(words[0])
    if pos > 0 and not name[pos - 1].isAlphaNumeric():
      match = 1
  (match, path.count('/'), name.len)

func rankPaths*(paths: openArray[string], home, text: string,
    includeHidden = false): seq[string] =
  ## Keeps the paths under `home` whose file name contains every word of
  ## `text`, best match first.
  let words = queryWords(text)
  if words.len == 0:
    return
  for path in paths:
    if isCandidate(path, home, words, includeHidden):
      result.add path
  result.sort(proc (a, b: string): int =
    result = cmp(score(a, words), score(b, words))
    if result == 0:
      result = cmp(a, b))

func displayDir*(path, home: string): string =
  ## The directory of `path`, with the home directory shown as `~`.
  let dir = path[0 ..< max(path.rfind('/'), 1)]
  if dir == home: "~"
  elif dir.startsWith(home & "/"): "~" & dir[home.len .. ^1]
  else: dir
