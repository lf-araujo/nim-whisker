import std/unittest
import ../src/whisker/query

func q(text: string): Query = initQuery(text, text)

suite "query.match":
  test "exact and prefix":
    check q("firefox").match("firefox") == 0x4
    check q("fire").match("firefox") == 0x8

  test "word boundary and substring":
    check q("web").match("firefox web browser") == 0x10
    check q("fox").match("firefox") == 0x80

  test "multiple words":
    check q("web brow").match("firefox web browser") == 0x10
    check q("fire brow").match("firefox web browser") == 0x20
    check q("brow fire").match("firefox web browser") == 0x40

  test "no match":
    check q("xyz").match("firefox") == noMatch
    check q("firefoxes").match("firefox") == noMatch
    check q("").match("firefox") == noMatch

  test "word boundary after a multi-byte space":
    check q("b").match("a b") == 0x10

suite "query.matchAsCharacters":
  test "initials":
    check q("fwb").matchAsCharacters("firefox web browser") == 0x100

  test "subsequence":
    check q("ffx").matchAsCharacters("firefox") == 0x200

  test "no match":
    check q("xf").matchAsCharacters("firefox") == noMatch
