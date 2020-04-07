import cligen

include "nmqtt.nim"


proc processClient(s: AsyncSocket) {.async.} =
  ## Create new client
  let ctx = MqttCtx()
  ctx.s = s
  ctx.state = Connecting

  while ctx.state in [Connecting, Connected]:
    try:
      var pkt = await ctx.recv()
      if pkt.typ == Notype:
        ctx.state = Error
        break
      await ctx.handle(pkt)
    except:
      # We are closing the socket, when we are disabling or disconnecting
      # the client. Therefor in these situations, the `ctx.state` must not
      # be set to `Error`, since we are breaking the socket on purpose.
      if ctx.state notin [Disabled, Disconnecting]:
        ctx.state = Error
      break

  if ctx.state == Error:
    # This happens on a ungraceful disconnects from the client.
    asyncCheck sendWill(ctx)

  if ctx.state in [Disconnected, Error]:
    # Remove the client from the register for subscribers.
    asyncCheck removeSubscriber(ctx)

  if ctx.state != Disabled:
    # The clients `state` is set to `Disabled`, if we cannot accept their
    # `Connect`-packet and respond with a `ConnAck`. Since we dont accept
    # the connection, the client is never added to `mqttbroker.connections`.
    if mqttbroker.connections.hasKey(ctx.clientid):
      mqttbroker.connections.del(ctx.clientid)

  if not ctx.s.isClosed():
    ctx.s.close()
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
  
  mqttbroker.version = 4
  mqttbroker.clientIdMaxLen = 65535
  mqttbroker.clientKickOld = false
  mqttbroker.emptyClientId = true
  mqttbroker.spacesInClientId = false
  mqttbroker.host = host
  mqttbroker.port = Port(port)
  mqttbroker.passClientId = false
  mqttbroker.maxConnections = 0
  #mqttbroker.retainExpire = 3600

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