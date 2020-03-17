# Copyright 2020 - Thomas T. Jarløv

import asyncdispatch, unittest, oids, random

include ../src/nmqtt

randomize()

# Test client main:
# ctxMain is an open connection, which can used in all the test. This
# connection is not to be closed.
let ctxMain = newMqttCtx("nmqttTestMain")
ctxMain.set_ping_interval(60) # To be removed
#ctxMain.set_host("test.mosquitto.org", 1883)
ctxMain.set_host("127.0.0.1", 1883)
waitFor ctxMain.start()

# Test clíent slave:
# ctxSlave is a client which may be closed and open. I should be closed
# after each test.
let ctxSlave = newMqttCtx("nmqttTestSlave")
ctxSlave.set_ping_interval(60) # To be removed
#ctxSlave.set_host("test.mosquitto.org", 1883)
ctxSlave.set_host("127.0.0.1", 1883)

# Test topic:
# Each test uses a new oid from the std lib = `$genOid()`

proc tout(t, s: string) =
  ## Print test data during test.
  stderr.write "  \e[17m" & t & " - " & s & "\e[0m\n"

proc tdata(t: string): (string, string) =
  ## Generate the test topic and message
  let topicTest = $genOid()
  let msg = $rand(99999999)
  tout(topicTest, t)
  return (topicTest, msg)

#include "connection.nim"
#include "subscribe.nim"
include "publish.nim"
#include "other.nim"