# Package

version = "0.1.0"
author = "Luis De Araujo"
description = "Nim rewrite of the Xfce Whisker Menu panel plugin"
license = "GPL-2.0-or-later"
srcDir = "src"

# Dependencies

requires "nim >= 2.0.0"

# Tasks

const
  pluginLib = "build/libwhisker-nim.so"
  libFlags = "--app:lib -d:release -d:noSignalHandler --hints:off"

task plugin, "Build the panel plugin (build/libwhisker-nim.so)":
  exec "nim c " & libFlags & " -o:" & pluginLib & " src/whisker_plugin.nim"

task preview, "Build the standalone preview (build/whisker-preview)":
  exec "nim c -d:release --hints:off -o:build/whisker-preview " &
    "src/whisker_preview.nim"

task test, "Run the unit tests, then the integration tests (need a display)":
  exec "nim c -r --hints:off -o:build/tquery tests/tquery.nim"
  exec "nim c -r --hints:off -o:build/tfilematch tests/tfilematch.nim"
  exec "nim c -r --hints:off -o:build/tintegration tests/tintegration.nim"
  # The store test writes under a throwaway property base; remove it.
  exec "xfconf-query -c xfce4-panel -p /whisker-nim-test -r -R"

task installUser, "Install the plugin for the current user (~/.local)":
  # xfce4-panel pairs ~/.local/share with the library directory name it was
  # built with, which is lib64 on some distributions (Solus among them).
  let
    libName =
      if dirExists("/usr/lib64/xfce4/panel/plugins"): "lib64" else: "lib"
    prefix = getEnv("HOME") & "/.local/"
    libDir = prefix & libName & "/xfce4/panel/plugins"
    dataDir = prefix & "share/xfce4/panel/plugins"
  exec "nimble plugin"
  mkDir libDir
  mkDir dataDir
  # Copy then rename: overwriting a library the running panel has loaded
  # would crash the panel.
  cpFile pluginLib, libDir & "/libwhisker-nim.so.new"
  mvFile libDir & "/libwhisker-nim.so.new", libDir & "/libwhisker-nim.so"
  cpFile "data/whisker-nim.desktop", dataDir & "/whisker-nim.desktop"
  echo "Installed to " & libDir
