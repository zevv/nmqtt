import cligen

include "nmqtt.nim"


proc processClient(s: AsyncSocket) {.async.} =
  ## Create new client
  let ctx = MqttCtx()
  ctx.s = s
  ctx.state = Connecting
  while ctx.state in {Connecting, Connected}:
    try:
      var pkt = await ctx.recv()
      if pkt.typ == Notype:
        break
      await ctx.handle(pkt)
      #asyncCheck ctx.handle(pkt)
    except:
      echo "Boom"
      ctx.state = Error

  if ctx.state != Disconnected:
    try:
      await removeSubscriber(ctx)
      await sendWill(ctx)
      when defined(verbose):
        echo ctx.clientid & " was lost"
    except:
      echo ctx.clientid & " crashed"

  ctx.state = Disabled


proc serve(ctx: AsyncSocket, host: string, port: int) {.async.} =
  var broker = newAsyncSocket()
  broker.setSockOpt(OptReuseAddr, true)
  broker.bindAddr(Port(port), host)
  broker.listen()

  while true:
    let client = await broker.accept()
    asyncCheck processClient(client)


proc nmqttBroker(config="", host="127.0.0.1", port: int=1883, verbose=0) {.async.} =
  ## CLI tool for broker

  let broker = newAsyncSocket()

  #if config != "":
  #  loadConfig
  #  if ssl:
  #    newContext()
  #    path to Key and Cert
  #  if passwords:
  #    password & username

  asyncCheck broker.serve(host, port)

  runForever()


when isMainModule:

  let topLvlUse = """${doc}
USAGE
  $command [options]
  $command [-c /path/to/config.conf]
  $command [-h hostIP -p port]

CONFIG
  Use the configuration file for detailed settings,
  such as SSL, adjusting keep alive timer, etc.

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]
  dispatch(nmqttBroker,
          doc="Subscribe to a topic on a MQTT-broker.",
          cmdName="nmqtt_broker",
          help={
            "config":    "absolute path to the config file",
            "host":     "IP-address to serve the broker on.",
            "port":     "network port to accept connecting from.",
            "verbose":     "verbose from 0-3."
          },
          short={
            "help": '?'
          },
          usage=topLvlUse
          )