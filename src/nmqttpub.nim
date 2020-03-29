import cligen
from os import getCurrentProcessId

include "nmqtt.nim"


proc nmqttPub(host="127.0.0.1", port: int=1883, ssl:bool=false, clientid="", username="", password="", topic, msg: string, qos=0, retain=false, verbose=false) =
  ## CLI tool for publish
  let ctx = newMqttCtx(if clientid != "": clientid else: "nmqtt_pub_" & $getCurrentProcessId())
  ctx.set_host(host, port, ssl)

  waitFor ctx.connect()
  waitFor ctx.publish(topic, msg, qos, retain)
  while ctx.workQueue.len() > 0:
    waitFor sleepAsync(100)
  waitFor ctx.disconnect()


when isMainModule:

  let topLvlUse = """${doc}
Usage:
  $command [options] -t {topic} -m {message}
  $command [-h host -p port -u username -P password] -t {topic} -m {message}

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]
  dispatch(nmqttPub,
          doc="Publish MQTT messages to a MQTT-broker.",
          cmdName="nmqttpub",
          help={
            "host":     "IP-address of the broker. Defaults to localhost.",
            "port":     "network port to connect too. Defaults to 1883 for plan MQTT and 8883 for MQTT with SSL.",
            "ssl":      "enable ssl. Auto-enabled on port 8883.",
            "clientid": "your connection ID. Defaults to nmqtt_pub_ appended with processID.",
            "username": "provide a username",
            "password": "provide a password",
            "topic":    "MQTT topic to publish to.",
            "qos":      "QOS: quality of service level to use for all messages. Defaults to 0.",
            "retain":   "retain messages on the broker."
          },
          short={
            "password": 'P',
            "help": '?',
            "ssl": '\0'
          },
          usage=topLvlUse
          )