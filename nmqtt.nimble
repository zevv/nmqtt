# Package
version       = "0.0.1"
author        = "zevv"
description   = "Native MQTT client library and binaries"
license       = "MIT"
srcDir        = "src"
bin           = @["nmqtt", "nmqtt_password", "nmqtt_pub", "nmqtt_sub"]
installFiles  = @["nmqtt.nim"]


# Dependencies
requires "nim >= 1.0.6"
requires "bcrypt >= 0.2.1"
requires "https://github.com/c-blake/cligen#36d5218"

from strutils import format

after install:
  var path: string

  echo "\nGenerate default nmqtt.conf? (y/N)"
  let genConf = readLineFromStdin()
  if genConf == "y" or genConf == "Y":
    let confPath = "/home/" & getEnv("USER") & "/.config/nmqtt"
    echo "\nAbsolute path to nmqtt config folder. Default: " & confPath

    path = readLineFromStdin()
    if path == "":
      path = confPath

    if not dirExists(path):
      mkDir(path)

    cpFile("config/nmqtt.conf", path & "/nmqtt.conf")
    echo "The brokers configuration has been saved at: " & path & "/nmqtt.conf"

  echo """

nmqtt v$1 has been installed.


LIBRARY:
Access the nim-libary with an import statement in your code:

  `import nmqtt`


BINARIES:
Access the binaries directly with. For help append `--help`.

  nmqtt
  nmqtt_password
  nmqtt_pub
  nmqtt_sub

""".format(version)