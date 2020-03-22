# Copyright 2020 - Thomas T. Jarløv

import asyncdispatch, unittest, oids, random

include ../src/nmqtt

randomize()

# Test client main:
# ctxMain is an open connection, which can used in all the test. This
# connection is not to be closed.
let ctxMain = newMqttCtx("nmqttTestMain")
#ctxMain.set_host("test.mosquitto.org", 1883)
ctxMain.set_host("127.0.0.1", 1883)
ctxMain.set_ping_interval(120)
waitFor ctxMain.start()

# Test clíent slave:
# ctxSlave is a client which may be closed and open. I should be closed
# after each test.
let ctxSlave = newMqttCtx("nmqttTestSlave")
#ctxSlave.set_host("test.mosquitto.org", 1883)
ctxSlave.set_host("127.0.0.1", 1883)

# Test clíent listen:
# ctxListen is a client which only should be used to make subscribe
# callbacks. Do not close it.
let ctxListen = newMqttCtx("nmqttTestListen")
#ctxSlave.set_host("test.mosquitto.org", 1883)
ctxListen.set_host("127.0.0.1", 1883)
ctxMain.set_ping_interval(120)
waitFor ctxListen.start()

proc tout(t, m, s: string) =
  ## Print test data during test.
  stderr.write "  \e[17m" & t & " - " & m & " - " & s & "\e[0m\n"

proc tdata(t: string): (string, string) =
  ## Generate the test topic and message
  let topicTest = $genOid()
  let msg = $rand(99999999)
  tout(topicTest, msg, t)
  return (topicTest, msg)

include "connection.nim"
include "subscribe.nim"
include "publish_retained.nim"
include "publish_qos.nim"

waitFor ctxMain.disconnect()
waitFor ctxListen.disconnect()