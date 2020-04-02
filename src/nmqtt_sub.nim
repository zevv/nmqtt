import cligen
from os import getCurrentProcessId

include "nmqtt.nim"


proc nmqttSub(host="127.0.0.1", port: int=1883, ssl:bool=false, clientid="", username="", password="", topic: string, qos=0, verbose=false) {.async.} =
  ## CLI tool for subscribe
  let ctx = newMqttCtx(if clientid != "": clientid else: "nmqtt_sub_" & $getCurrentProcessId())
  ctx.set_host(host, port, ssl)

  await ctx.start()

  proc on_data(topic, msg: string) =
    echo topic, ": ", msg

  await ctx.subscribe(topic, qos, on_data)

  runForever()


when isMainModule:

  let topLvlUse = """${doc}
Usage:
  $command [options] -t {topic}
  $command [-h host -p port -u username -P password] -t {topic}

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]
  dispatch(nmqttSub,
          doc="Subscribe to a topic on a MQTT-broker.",
          cmdName="nmqtt_sub",
          help={
            "host":     "IP-address of the broker. Defaults to localhost.",
            "port":     "network port to connect too. Defaults to 1883 for plan MQTT and 8883 for MQTT with SSL.",
            "ssl":      "enable ssl. Auto-enabled on port 8883.",
            "clientid": "your connection ID. Defaults to nmqtt_pub_ appended with processID.",
            "username": "provide a username",
            "password": "provide a password",
            "topic":    "MQTT topic to publish to.",
            "qos":      "QOS: quality of service level to use for all messages. Defaults to 0.",
          },
          short={
            "password": 'P',
            "help": '?',
            "ssl": '\0'
          },
          usage=topLvlUse
          )