import std/unittest
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
