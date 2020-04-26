import cligen

from os import getCurrentProcessId

import utils/version

include "../nmqtt.nim"


proc handler() {.noconv.} =
  ## Catch ctrl+c from user
  echo ""
  quit(0)


proc nmqttPub(host="127.0.0.1", port=1883, ssl=false, clientid="", username="", password="", topic, msg: string, qos=0, retain=false, repeat=0, repeatdelay=0, willtopic="", willmsg="", willqos=0, willretain=false, verbosity=0) =
  ## CLI tool for publish
  if verbosity >= 1:
    echo "Running nmqtt_pub v" & nmqttVersion

  let ctx = newMqttCtx(if clientid != "": clientid else: "nmqttpub-" & $getCurrentProcessId())
  ctx.set_host(host, port, ssl)

  if username != "" or password != "":
    ctx.set_auth(username, password)

  # Set the will message
  if willretain and (willtopic == "" or willmsg == ""):
    echo "Error: Will-retain giving, but no topic given"
    quit()
  elif willtopic != "" and willmsg != "":
    ctx.set_will(willtopic, willmsg, willqos, willretain)

  # Set the verbosity
  ctx.set_verbosity(verbosity)

  # Control CTRL+c hook
  setControlCHook(handler)

  # Connect to broker
  waitFor ctx.connect()

  # Publish message.
  # If --repeat is specified, repeat N times with Z delay.
  if repeat == 0:
    waitFor ctx.publish(topic, msg, qos, retain)
  else:
    for i in 0..repeat-1:
      waitFor ctx.publish(topic, msg, qos, retain)
      if repeatdelay > 0: waitFor sleepAsync (repeatdelay * 1000)

  # Check that the message has been succesfully send
  while ctx.workQueue.len() > 0:
    waitFor sleepAsync(100)

  # Disconnect from broker
  waitFor ctx.disconnect()


when isMainModule:

  let topLvlUse = """nmqtt_pub is a MQTT client for publishing messages to a MQTT-broker.
nmqtt_pub is based upon nmqtt version """ & nmqttVersion & """


Usage:
  $command [options] -t {topic} -m {message}
  $command [-h host -p port -u username -P password] -t {topic} -m {message}

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDescrip]
  dispatchGen(nmqttPub,
          cmdName="nmqtt_pub",
          help={
            "host":         "IP-address of the broker.",
            "port":         "network port to connect too.",
            "ssl":          "use ssl.",
            "clientid":     "your connection ID. Defaults to nmqttpub- appended with processID.",
            "username":     "provide a username",
            "password":     "provide a password",
            "topic":        "mqtt topic to publish to.",
            "msg":          "message payload to send.",
            "qos":          "quality of service level to use for all messages.",
            "retain":       "retain messages on the broker.",
            "repeat":       "repeat the publish N times.",
            "repeatdelay":  "if using --repeat, wait N seconds between publish. Defaults to 0.",
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
            "willtopic": '\0',
            "willmsg": '\0',
            "willqos": '\0',
            "willretain": '\0'
          },
          usage=topLvlUse,
          dispatchName="publisher"
          )

  cligenQuit publisher(skipHelp=true)