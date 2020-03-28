# Package
version       = "0.0.1"
author        = "zevv"
description   = "Native MQTT client library"
license       = "MIT"
srcDir        = "src"
bin           = @["nmqttpub", "nmqttsub"]


# Dependencies
requires "nim >= 1.0.6"
requires "cligen >= 0.9.43"