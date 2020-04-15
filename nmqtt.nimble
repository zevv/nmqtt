# Package
version       = "0.0.1"
author        = "zevv"
description   = "Native MQTT client library and binaries"
license       = "MIT"
srcDir        = "src"
bin           = @["nmqtt_pub", "nmqtt_sub", "nmqtt_broker"]


# Dependencies
requires "nim >= 1.0.6"
requires "https://github.com/c-blake/cligen#36d5218"