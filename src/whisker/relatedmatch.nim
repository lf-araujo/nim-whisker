## Choosing what to look for when finding files related to a file, and
## merging the two kinds of related files. Pure Nim, no GTK.
##
## "Similar" files are found by a full-text search for a few words of the
## file's title, so the title has to come from somewhere useful: the
## document's own title, a Markdown/Org front-matter title, or failing
## those the file name with its noise removed.

import std/[algorithm, sequtils, strutils]

const stopWords = [
  # English
  "about", "after", "also", "among", "and", "between", "from", "into",
  "more", "than", "that", "their", "there", "these", "this", "those",
  "through", "under", "using", "what", "when", "which", "while", "with",
  "within", "without", "copy", "final", "draft", "version",
  # Portuguese
  "como", "entre", "este", "esta", "isso", "mais", "para", "pela", "pelo",
  "sobre", "uma", "versao", "versão"]

func frontMatterTitle*(text: string): string =
  ## The title in a YAML front-matter block (`---` lines at the top) or Org
  ## `#+title:` line; empty if there is none. `title:` wins over `parent:`,
  ## which Better Notes uses for the title of the item a note belongs to.
  var parent = ""
  let lines = text.splitLines()
  if lines.len > 0 and lines[0].strip() == "---":
    for i in 1 ..< lines.len:
      let line = lines[i].strip()
      if line == "---":
        break
      for key in ["title:", "parent:"]:
        if line.toLowerAscii().startsWith(key):
          let value = line[key.len .. ^1].strip().strip(chars = {'\'', '"'})
          if key == "title:" and value.len > 0:
            return value
          parent = value
  else:
    for line in lines:
      if line.toLowerAscii().startsWith("#+title:"):
        return line[8 .. ^1].strip()
  parent

func isKeyLike(word: string): bool =
  ## Zotero item keys and similar ids, e.g. "ZUPZRER2": eight capitals and
  ## digits with at least one digit.
  word.len == 8 and word.allCharsInSet({'A' .. 'Z', '0' .. '9'}) and
    word.anyIt(it in {'0' .. '9'})

func keyWords*(title: string, count = 5): seq[string] =
  ## Up to `count` distinctive words of `title`, longest first: lower case,
  ## without numbers, ids, short words and common words.
  var
    words: seq[string]
    word = ""
  for c in title & " ":
    if c.isAlphaNumeric() or ord(c) >= 0x80:
      word.add c
    elif word.len > 0:
      if not isKeyLike(word):
        let lower = word.toLowerAscii()
        if lower.len >= 4 and not lower.allCharsInSet({'0' .. '9'}) and
            lower notin stopWords and lower notin words:
          words.add lower
      word = ""
  words.sort(proc (a, b: string): int = cmp(b.len, a.len), SortOrder.Ascending)
  words[0 ..< min(count, words.len)]

func fileNameTitle*(path: string): string =
  ## The file name of `path` without its extension.
  let name = path[path.rfind('/') + 1 .. ^1]
  let dot = name.rfind('.')
  if dot > 0: name[0 ..< dot] else: name

func isUsefulTitle*(title: string): bool =
  ## Whether a document's own title says what it is about. Many PDFs carry
  ## the name of the file they were made from ("Microsoft Word - x.docx")
  ## or nothing useful at all.
  let lower = title.toLowerAscii()
  keyWords(title).len >= 3 and not lower.startsWith("microsoft") and
    ".doc" notin lower and ".tex" notin lower and "untitled" notin lower
