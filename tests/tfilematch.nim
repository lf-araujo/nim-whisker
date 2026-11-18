import std/[strutils, unittest]
import ../src/whisker/filematch

const home = "/home/u"

suite "filematch":
  test "isFileQuery skips short queries, search actions and URIs":
    check isFileQuery("report", 3)
    check not isFileQuery("re", 3)
    check not isFileQuery("!w nim", 3)
    check not isFileQuery("-thesis", 3)
    check not isFileQuery("https://x.org", 3)

  test "keeps only visible files under home whose name has every word":
    let paths = ["/usr/share/report.txt", "/home/u/.cache/report.txt",
      "/home/u/docs/Report 2026.pdf", "/home/u/report/other.txt",
      "/home/user2/report.txt"]
    check rankPaths(paths, home, "report") == @["/home/u/docs/Report 2026.pdf"]
    check rankPaths(paths, home, "2026 report") ==
      @["/home/u/docs/Report 2026.pdf"]
    check rankPaths(paths, home, "report", includeHidden = true).len == 2
    check rankPaths(paths, home, "  ").len == 0

  test "ranks prefix, then word start, then substring; shallow first":
    let paths = ["/home/u/a/b/myreport.txt", "/home/u/a/final-report.txt",
      "/home/u/a/b/report.txt", "/home/u/report.md"]
    check rankPaths(paths, home, "report") == @["/home/u/report.md",
      "/home/u/a/b/report.txt", "/home/u/a/final-report.txt",
      "/home/u/a/b/myreport.txt"]

  test "displayDir abbreviates home":
    check displayDir("/home/u/x.txt", home) == "~"
    check displayDir("/home/u/a/x.txt", home) == "~/a"
    check displayDir("/etc/x.txt", home) == "/etc"

  test "ftsMatch makes prefix terms and drops punctuation":
    check ftsMatch("Spons") == "spons*"
    check ftsMatch("department  energy") == "department* energy*"
    check ftsMatch("TDB34VVX.md") == "tdb34vvx* md*"
    check ftsMatch("a\"b' OR c") == "a* b* or* c*"
    check ftsMatch("orientações") == "orientações*"
    check ftsMatch("-- ?? ") == ""

  test "a fold makes accents match":
    func noAccents(text: string): string =
      text.multiReplace(("ç", "c"), ("õ", "o")).toLowerAscii()
    let paths = ["/home/u/n/Orientações-SZIG.md"]
    check rankPaths(paths, home, "orientacoes").len == 0
    check rankPaths(paths, home, "orientacoes", fold = noAccents) == @paths

  test "visiblePaths keeps order, drops hidden, outside and repeats":
    check visiblePaths(["/home/u/b.md", "/etc/x", "/home/u/.x/y.md",
      "/home/u/a.md", "/home/u/b.md"], home) == @["/home/u/b.md",
      "/home/u/a.md"]

  test "mergeResults keeps rows for content matches":
    let names = @["n1", "n2", "n3", "n4", "n5"]
    check mergeResults(names, ["c1", "c2", "c3"], 4, 2) ==
      @["n1", "n2", "c1", "c2"]
    check mergeResults(names, ["c1"], 4, 2) == @["n1", "n2", "n3", "c1"]
    check mergeResults(names, [], 4, 2) == @["n1", "n2", "n3", "n4"]
    check mergeResults(["n1"], ["c1", "c2", "c3", "c4"], 4, 2) ==
      @["n1", "c1", "c2", "c3"]
    check mergeResults(names, ["n1", "c1"], 4, 2) ==
      @["n1", "n2", "n3", "c1"] # A name match is not repeated.
    check mergeResults(names, ["c1", "c2"], 4, 0) ==
      @["n1", "n2", "n3", "n4"]
