## Search query matching, ported from upstream `query.cpp`.
##
## Pure Nim with no GTK dependency. Callers pass strings that are already
## normalized and case-folded; lower relevancy values sort first.

import std/[strutils, unicode]

type
  Query* = object
    raw: string
    folded: string
    words: seq[string]

const noMatch* = high(uint32)

func initQuery*(raw, folded: string): Query =
  ## `folded` is the normalized, case-folded form of `raw`.
  Query(raw: raw, folded: folded, words: strutils.splitWhitespace(folded))

func raw*(query: Query): string = query.raw

func isEmpty*(query: Query): bool = query.raw.len == 0

func isStartWord(haystack: string, pos: int): bool =
  pos == 0 or haystack.lastRune(pos - 1)[0].isWhiteSpace()

func match*(query: Query, haystack: string): uint32 =
  ## Relevancy of `haystack` for the whole query, or `noMatch`.
  if query.folded.len == 0 or query.folded.len > haystack.len:
    return noMatch
  let pos = haystack.find(query.folded)
  if pos == 0:
    return if haystack.len == query.folded.len: 0x4 else: 0x8
  if pos > 0 and isStartWord(haystack, pos):
    return 0x10
  if query.words.len > 1:
    # Query words in order, each starting a word.
    var searchPos = 0
    for word in query.words:
      if searchPos >= 0:
        searchPos = haystack.find(word, searchPos)
        if searchPos >= 0 and not isStartWord(haystack, searchPos):
          searchPos = -1
    if searchPos >= 0:
      return 0x20
    # Query words in any order, each starting a word.
    var allFound = true
    for word in query.words:
      if allFound:
        let wordPos = haystack.find(word)
        allFound = wordPos >= 0 and isStartWord(haystack, wordPos)
    if allFound:
      return 0x40
  if pos >= 0:
    return 0x80
  noMatch

func matchAsCharacters*(query: Query, haystack: string): uint32 =
  ## Matches the query's characters as word initials (0x100) or as a
  ## subsequence (0x200) of `haystack`.
  if query.folded.len == 0 or query.folded.len > haystack.len:
    return noMatch
  let needle = query.folded.toRunes()
  var
    startWord = true
    initialsPos = 0
    sequencePos = 0
  for c in haystack.runes:
    if startWord:
      if initialsPos < needle.len and c == needle[initialsPos]:
        inc initialsPos
      startWord = false
    elif c.isWhiteSpace():
      startWord = true
    if sequencePos < needle.len and c == needle[sequencePos]:
      inc sequencePos
  if initialsPos == needle.len:
    0x100
  elif sequencePos == needle.len:
    0x200
  else:
    noMatch
