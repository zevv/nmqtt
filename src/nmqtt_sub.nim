import cligen
from os import getCurrentProcessId

include "nmqtt.nim"


let ctx = newMqttCtx("nmqtt_sub_" & $getCurrentProcessId())


proc handler() {.noconv.} =
  ## Catch ctrl+c from user
  waitFor ctx.disconnect()
  quit(0)


proc nmqttSub(host="127.0.0.1", port: int=1883, ssl:bool=false, clientid="", username="", password="", topic: string, qos=0, keepalive=60, removeretained=false, willtopic="", willmsg="", willqos=0, willretain=false, verbose=false) {.async.} =
  ## CLI tool for subscribe
  let ctx = newMqttCtx(if clientid != "": clientid else: "nmqttsub-" & $getCurrentProcessId())

  if port == 8883:
    ctx.set_host(host, port, true)
  else:
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

  # Connec to broker
  await ctx.start()

  # Remove retained messages
  if removeretained:
    waitFor ctx.publish(topic, "", 0, true)

  # Callback for subscribe
  proc on_data(topic, msg: string) =
    echo topic, ": ", msg

  # Subscribe to topic
  await ctx.subscribe(topic, qos, on_data)

  # Control CTRL+c hook
  setControlCHook(handler)

  runForever()


when isMainModule:

  let topLvlUse = """${doc}
Usage:
  $command [options] -t {topic}
  $command [-h host -p port -u username -P password] -t {topic}

OPTIONS
$options
"""
  #clCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]
  clCfg.hTabCols = @[clOptKeys, clDescrip]
  dispatch(nmqttSub,
          doc="Subscribe to a topic on a MQTT-broker.",
          cmdName="nmqtt_sub",
          help={
            "host":         "IP-address of the broker. Defaults to 127.0.0.1",
            "port":         "network port to connect too. Defaults to 1883.",
            "ssl":          "enable ssl. Auto-enabled on port 8883.",
            "clientid":     "your connection ID. Defaults to nmqtt_pub_ appended with processID.",
            "username":     "provide a username",
            "password":     "provide a password",
            "topic":        "MQTT topic to publish to.",
            "qos":          "quality of service level to use for all messages. Defaults to 0.",
            "keepalive":    "keep alive in seconds for this client. Defaults to 60.",
            "removeretained": "clear any retained messages on the topic",
            "willtopic":    "set the will's topic",
            "willmsg":      "set the will's message",
            "willqos":      "set the will's quality of service",
            "willretain":   "set to retain the will message"
          },
          short={
            "password": 'P',
            "help": '?',
            "ssl": '\0',
            "willtopic": '\0',
            "willmsg": '\0',
            "willqos": '\0',
            "willretain": '\0',
            "removeretained": '\0'
          },
          usage=topLvlUse
          )