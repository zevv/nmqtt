import macros
from strutils import replace, splitLines, split, contains
from os import `/`

macro nimbleVersion(): void =
  let n = staticRead(currentSourcePath().replace("/src/utils/version.nim") / "nmqtt.nimble")
  var v: string
  for line in n.splitLines:
    let l = split(line, " = ")
    if l[0].contains("version"):
      v = l[1].replace("\"", "")
      break
  result = parseStmt("const nmqttVersion* = \"" & v & "\"")

nimbleVersion()