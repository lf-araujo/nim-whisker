## Filtering and ranking of file search candidates. Pure Nim, no GTK.

import std/[algorithm, strutils]

type
  Fold* = proc (text: string): string {.nimcall, noSideEffect.}
    ## Maps a name or query word to the form compared, e.g. lower case
    ## without accents.

func lowerFold*(text: string): string =
  ## The default `Fold`: ASCII lower case.
  text.toLowerAscii()

func isFileQuery*(text: string, minChars: int): bool =
  ## Whether `text` should be searched for as a file name. Short queries and
  ## ones that look like a search action (`!w foo`, `?foo`) or a URI are not.
  let query = text.strip()
  query.len >= minChars and query[0] notin {'!', '?', '#'} and
    "://" notin query

func queryWords*(text: string, fold: Fold = lowerFold): seq[string] =
  ## The folded words every result's file name must contain.
  for word in strutils.splitWhitespace(text):
    result.add fold(word)

func ftsMatch*(text: string): string =
  ## The LocalSearch full-text query for `text`: each word as a prefix term,
  ## all required ("Report-2026.pdf" gives "report* 2026* pdf*"). Punctuation
  ## separates words, as full-text syntax would read it as operators.
  var
    terms: seq[string]
    term = ""
  for c in text.toLowerAscii() & " ":
    if c.isAlphaNumeric() or ord(c) >= 0x80:
      term.add c
    elif term.len > 0:
      terms.add term & "*"
      term = ""
  terms.join(" ")

func baseName(path: string): string =
  path[path.rfind('/') + 1 .. ^1]

func isVisible(path, home: string, includeHidden: bool): bool =
  path.startsWith(home & "/") and
    (includeHidden or "/." notin path[home.len .. ^1])

func isCandidate(path, home: string, words: seq[string],
    includeHidden: bool, fold: Fold): bool =
  if not isVisible(path, home, includeHidden):
    return false
  let name = fold(baseName(path))
  for word in words:
    if word notin name:
      return false
  true

func score(path: string, words: seq[string],
    fold: Fold): tuple[match, depth, len: int] =
  ## Lower is better: name starts with the query, then a word of the name
  ## does, then any substring; shallower and shorter paths break ties.
  let name = fold(baseName(path))
  var match = 2
  if name.startsWith(words[0]):
    match = 0
  else:
    let pos = name.find(words[0])
    if pos > 0 and not name[pos - 1].isAlphaNumeric():
      match = 1
  (match, path.count('/'), name.len)

func rankPaths*(paths: openArray[string], home, text: string,
    includeHidden = false, fold: Fold = lowerFold): seq[string] =
  ## Keeps the paths under `home` whose file name contains every word of
  ## `text`, best match first.
  let words = queryWords(text, fold)
  if words.len == 0:
    return
  for path in paths:
    if isCandidate(path, home, words, includeHidden, fold):
      result.add path
  result.sort(proc (a, b: string): int =
    result = cmp(score(a, words, fold), score(b, words, fold))
    if result == 0:
      result = cmp(a, b))

func visiblePaths*(paths: openArray[string], home: string,
    includeHidden = false): seq[string] =
  ## The paths under `home`, hidden ones dropped unless `includeHidden`,
  ## in their original order and without repeats. For content matches.
  for path in paths:
    if isVisible(path, home, includeHidden) and path notin result:
      result.add path

func mergeResults*(names, contents: openArray[string],
    limit, contentSlots: int): seq[string] =
  ## At most `limit` results: name matches first, then content matches.
  ## Up to `contentSlots` rows are kept for content matches when there are
  ## any; rows one kind leaves unused go to the other. A path found both
  ## ways is shown once, as a name match.
  var extra: seq[string]
  for path in contents:
    if path notin names and path notin extra:
      extra.add path
  let nameCount = min(names.len, limit - min(contentSlots, extra.len))
  for i in 0 ..< nameCount:
    result.add names[i]
  for path in extra:
    if result.len >= limit:
      break
    result.add path

func displayDir*(path, home: string): string =
  ## The directory of `path`, with the home directory shown as `~`.
  let dir = path[0 ..< max(path.rfind('/'), 1)]
  if dir == home: "~"
  elif dir.startsWith(home & "/"): "~" & dir[home.len .. ^1]
  else: dir
