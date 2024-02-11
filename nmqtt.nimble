# Package
version       = "1.0.6"
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
requires "cligen >= 0.9.45"
when not defined(Windows):
  requires "bcrypt >= 0.2.1"


from strutils import format


task test, "Runs the test suite.":
  exec "nimble c -y -r tests/tester"


task setup, "Generate default nmqtt configuration file":
  var path: string

  echo "\nGenerate default nmqtt.conf? (y/N)"
  let genConf = readLineFromStdin()
  if genConf == "y" or genConf == "Y":
    let confPath = "/home/" & getEnv("USER") & "/.nmqtt"
    echo "\nSpecify the absolute path to the nmqtt config folder.\nPress enter to use default path: " & confPath

    path = readLineFromStdin()
    if path == "":
      path = confPath

    if not dirExists(path):
      mkDir(path)

    cpFile("config/nmqtt.conf", path & "/nmqtt.conf")

    echo """
___________________________________________________________

nmqtt v$1

The brokers configuration has been saved at:
  $2/nmqtt.conf

You can now run the broker with:
  nmqtt -c $2/nmqtt.conf

___________________________________________________________

""".format(version, path)
