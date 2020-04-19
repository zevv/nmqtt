import cligen

from os import getCurrentProcessId
from strutils import split

import utils/version

include "nmqtt.nim"


let ctx = newMqttCtx("nmqttsub-" & $getCurrentProcessId())


proc handler() {.noconv.} =
  ## Catch ctrl+c from user
  echo ""
  waitFor ctx.disconnect()
  quit(0)

proc nmqttSub(host="127.0.0.1", port=1883, ssl=false, clientid="", username="", password="", topic: string, qos=0, keepalive=60, removeretained=false, willtopic="", willmsg="", willqos=0, willretain=false, verbosity=0) {.async.} =
  ## CLI tool for subscribe
  if verbosity >= 1:
    echo "Running nmqtt_sub v" & nmqttVersion

  if clientid != "":
    ctx.clientid = clientid

  ctx.set_host(host, port, ssl)

  if username != "" or password != "":
    ctx.set_auth(username, password)

  # Set the ping interval/keep alive
  ctx.set_ping_interval(keepalive)

  # Set the will message
  if willretain and (willtopic == "" or willmsg == ""):
    echo "Error: Will-retain giving, but no topic given"
    quit(0)
  elif willtopic != "" and willmsg != "":
    ctx.set_will(willtopic, willmsg, willqos, willretain)

  # Set the verbosity
  ctx.set_verbosity(verbosity)

  # Connec to broker
  await ctx.start()

  # Loop through topics
  for t in topic.split(","):
    # Remove retained messages
    if removeretained:
      waitFor ctx.publish(t, "", 0, true)

    # Callback for subscribe
    proc on_data(t, msg: string) =
      echo t, ": ", msg

    # Subscribe to topic
    await ctx.subscribe(t, qos, on_data)
    if ctx.verbosity >= 1:
      ctx.dbg "Subscribing to: " & t

  # Control CTRL+c hook
  setControlCHook(handler)

  runForever()


when isMainModule:

  let topLvlUse = """nmqtt_sub is a MQTT client that will subscribe to a topic on a MQTT-broker.
nmqtt_sub is based upon nmqtt version """ & nmqttVersion & """


Usage:
  $command [options] -t {topic}
  $command [-h host -p port -u username -P password] -t {topic}

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDescrip]
  dispatchGen(nmqttSub,
          doc="Subscribe to a topic on a MQTT-broker.",
          cmdName="nmqtt_sub",
          help={
            "host":         "IP-address of the broker. Defaults to 127.0.0.1",
            "port":         "network port to connect too. Defaults to 1883.",
            "ssl":          "use ssl.",
            "clientid":     "your connection ID. Defaults to nmqttsub- appended with processID.",
            "username":     "provide a username",
            "password":     "provide a password",
            "topic":        "MQTT topic to subscribe too. For multipe topics, separate them by comma.",
            "qos":          "quality of service level to use for all messages. Defaults to 0.",
            "keepalive":    "keep alive in seconds for this client. Defaults to 60.",
            "removeretained": "clear any retained messages on the topic",
            "willtopic":    "set the will's topic",
            "willmsg":      "set the will's message",
            "willqos":      "set the will's quality of service",
            "willretain":   "set to retain the will message",
            "verbosity":    "set the verbosity level from 0-2. Defaults to 0."
          },
          short={
            "password": 'P',
            "help": '?',
            "ssl": '\0',
            "verbosity": 'v',
            "willtopic": '\0',
            "willmsg": '\0',
            "willqos": '\0',
            "willretain": '\0',
            "removeretained": '\0'
          },
          usage=topLvlUse,
          dispatchName="subscriber"
          )

  cligenQuit subscriber(skipHelp=true)

  runForever()