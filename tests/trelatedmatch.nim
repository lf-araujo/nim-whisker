import std/unittest
import ../src/whisker/relatedmatch

suite "relatedmatch":
  test "front matter: title wins over parent; Org title":
    check frontMatterTitle("---\ntags: []\nparent: 'Conditions for X'\n---\nbody") ==
      "Conditions for X"
    check frontMatterTitle("---\ntitle: \"Mine\"\nparent: Other\n---\n") == "Mine"
    check frontMatterTitle("#+TITLE: Count data models\n* Intro") ==
      "Count data models"
    check frontMatterTitle("no front matter\nparent: x") == ""
    check frontMatterTitle("---\nparent: x\n---\n---\ntitle: late\n") == "x"

  test "keyWords: longest distinctive words, no ids, numbers or stop words":
    check keyWords("Conditions for the Equivalence of the Autoregressive " &
      "Latent Trajectory Model and a Latent Growth Curve Model With " &
      "Autoregressive Disturbances") ==
      @["autoregressive", "disturbances", "equivalence", "conditions",
        "trajectory"]
    check keyWords("Mktero-Markdown-Snapshot-ZUPZRER2") ==
      @["markdown", "snapshot", "mktero"]
    check keyWords("2026-VIPBG-seminar") == @["seminar", "vipbg"]
    check keyWords("Orientações sobre realização", 2) ==
      @["orientações", "realização"]
    check keyWords("a b 12 of").len == 0

  test "isUsefulTitle rejects converter names and thin titles":
    check isUsefulTitle("Conditions for the Equivalence of Models")
    check not isUsefulTitle("Microsoft Word - paper final.docx")
    check not isUsefulTitle("untitled document draft")
    check not isUsefulTitle("Slides")

  test "fileNameTitle drops the extension":
    check fileNameTitle("/a/b/2026-VIPBG-seminar.pdf") == "2026-VIPBG-seminar"
    check fileNameTitle("/a/.hidden") == ".hidden"
