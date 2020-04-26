# Package
version       = "1.0.1"
author        = "zevv & ThomasTJdev"
description   = "Native MQTT library and binaries for publishing, subscribing and broker"
license       = "MIT"
bin           = @["nmqtt/nmqtt", "nmqtt/nmqtt_password", "nmqtt/nmqtt_pub", "nmqtt/nmqtt_sub"]
binDir        = "bin"
installFiles  = @["nmqtt.nim"]
installDirs   = @["config"]
skipDirs      = @["tests", "nmqtt"]

# Dependencies
requires "nim >= 1.0.6"
requires "bcrypt >= 0.2.1"
requires "cligen >= 0.9.45"

from strutils import format


task test, "Runs the test suite.":
  exec "nimble c -y -r tests/tester"


after install:
  var path: string

  echo "\nGenerate default nmqtt.conf? (y/N)"
  let genConf = readLineFromStdin()
  if genConf == "y" or genConf == "Y":
    let confPath = "/home/" & getEnv("USER") & "/.nmqtt"
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
Access the binaries directly with the commands below. For help append `--help`.

  nmqtt
  nmqtt_password
  nmqtt_pub
  nmqtt_sub

""".format(version)