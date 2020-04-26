import asyncdispatch, unittest, oids, random

var testDmp: seq[seq[string]]

when not defined(test):
  echo "Please run with -d:test, exiting"
  quit()

include ../src/nmqtt

randomize()

# Test client main:
# ctxMain is an open connection, which can used in all the test. This
# connection is not to be closed.
let ctxMain = newMqttCtx("nmqttTestMain")
#ctxMain.set_host("test.mosquitto.org", 1883)
ctxMain.set_host("127.0.0.1", 1883)
ctxMain.set_ping_interval(1200)
waitFor ctxMain.start()

# Test clíent slave:
# ctxSlave is a client which may be closed and open. It should be closed
# after each test.
let ctxSlave = newMqttCtx("nmqttTestSlave")
#ctxSlave.set_host("test.mosquitto.org", 1883)
ctxSlave.set_host("127.0.0.1", 1883)
ctxSlave.set_ping_interval(1200)

# Test clíent listen:
# ctxListen is a client which only should be used to make subscribe
# callbacks. Do not close it.
let ctxListen = newMqttCtx("nmqttTestListen")
#ctxSlave.set_host("test.mosquitto.org", 1883)
ctxListen.set_host("127.0.0.1", 1883)
ctxMain.set_ping_interval(1200)
waitFor ctxListen.start()

proc tout(t, m, s: string) =
  ## Print test data during test.
  stderr.write "  \e[17m" & t & " - " & m & " - " & s & "\e[0m\n"

proc tdata(t: string): (string, string) =
  ## Generate the test topic and message
  let topicTest = $genOid()
  let msg = $rand(99999999)
  tout(topicTest, msg, t)
  testDmp = @[]
  return (topicTest, msg)

waitFor sleepAsync(1500) # Let the clients connect

include "connection.nim"
include "subscribe.nim"
include "unsubscribe.nim"
include "publish.nim"
include "publish_qos.nim"
include "ping.nim"
include "tools.nim"
include "willmsg.nim"          # Contains retained msgs
include "publish_retained.nim" # Contains retained msgs
                               #
                               # When the test contains retained msgs,
                               # it needs to be the last test, since it
                               # will store msg's, which will be caught
                               # in the subscribe test on `#`.

waitFor ctxMain.disconnect()
waitFor ctxListen.disconnect()