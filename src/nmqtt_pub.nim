import cligen
from os import getCurrentProcessId

include "nmqtt.nim"


proc nmqttPub(host="127.0.0.1", port: int=1883, ssl:bool=false, clientid="", username="", password="", topic, msg: string, qos=0, retain=false, willtopic="", willmsg="", willqos=0, willretain=false, verbose=false) =
  ## CLI tool for publish
  let ctx = newMqttCtx(if clientid != "": clientid else: "nmqtt_pub_" & $getCurrentProcessId())
  ctx.set_host(host, port, ssl)

  if willretain and (willtopic == "" or willmsg == ""):
    echo "Error: Will-retain giving, but no topic given"
    quit()
  elif willtopic != "" and willmsg != "":
    ctx.set_will(willtopic, willmsg, willqos, willretain)

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
  #clCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]
  clCfg.hTabCols = @[clOptKeys, clDescrip]
  dispatch(nmqttPub,
          doc="Publish MQTT messages to a MQTT-broker.",
          cmdName="nmqtt_pub",
          help={
            "host":     "IP-address of the broker.",
            "port":     "network port to connect too.",
            "ssl":      "enable ssl. Auto-enabled on port 8883.",
            "clientid": "your connection ID. Defaults to nmqtt_pub_ appended with processID.",
            "username": "provide a username",
            "password": "provide a password",
            "topic":    "MQTT topic to publish to.",
            "qos":      "quality of service level to use for all messages.",
            "retain":   "retain messages on the broker.",
            "willtopic":"set the will's topic",
            "willmsg":  "set the will's message",
            "willqos":  "set the will's quality of service",
            "willretain":"set to retain the will message"
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
          usage=topLvlUse
          )