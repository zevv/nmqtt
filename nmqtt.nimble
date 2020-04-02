# Package
version       = "0.0.1"
author        = "zevv"
description   = "Native MQTT client library and binaries"
license       = "MIT"
srcDir        = "src"
bin           = @["nmqtt_pub", "nmqtt_sub"]


# Dependencies
requires "nim >= 1.0.6"
requires "cligen >= 0.9.43"