#
# Code for the broker
# --------------------
#
# This file contains the code for the MQTT broker. Broker specific procs
# and CLI are defined within this file, while all base MQTT-code is included
# from the main library file (`../nmqtt.nim`).
#
# This file is named the same as the library file, so when the binaries are
# generated, the brokers binary will be named `nmqtt`.
#

include "../nmqtt.nim"

proc keepAliveMonitor(ctx: MqttCtx) {.async.} =
  ctx.lastAction = epochTime()
  # The keep alive time is one and a half times the Keep Alive periode [MQTT-3.1.2-24]
  let keepAlive = toFloat(ctx.keepAlive.int) * 1.5 * 1000
  while ctx.state in [Connecting, Connected]:
    let saveLastAction = ctx.lastAction
    await sleepAsync(keepAlive)
    if ctx.lastAction <= saveLastAction:
      ctx.state = Error
      ctx.s.close()
      if mqttbroker.verbosity >= 1:
        verbose("Connections >> " & ctx.clientid & " was disconnected. Keep alive time overdue.")
      break


proc processClient(s: AsyncSocket) {.async.} =
  ## Create new client
  let ctx = MqttCtx()
  ctx.s = s
  ctx.state = Connecting
  ctx.sslOn = mqttbroker.sslOn

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

  if not ctx.beenConnected:
    # When the client hasn't been connected to the broker, then we don't
    # want to check for LWT, subscriptions etc. - we just want to close
    # and remove the socket!
    try:
      ctx.s.close()
    except:
      if mqttbroker.verbosity >= 3 and ctx.sslOn:
        wrn("Someone is trying to connect, properly without SSL.")
    return

  if ctx.state == Error and ctx.beenConnected:
    # This happens on a ungraceful disconnects from the client.
    asyncCheck sendWill(ctx)

  if ctx.state in [Disconnected, Error] and ctx.beenConnected:
    # Remove the client from the register for subscribers.
    asyncCheck removeSubscriber(ctx)

  if ctx.state != Disabled and ctx.beenConnected:
    # The clients `state` is set to `Disabled`, if we cannot accept their
    # `Connect`-packet and respond with a `ConnAck`. Since we dont accept
    # the connection, the client is never added to `mqttbroker.connections`.
    if mqttbroker.connections.hasKey(ctx.clientid):
      mqttbroker.connections.del(ctx.clientid)

    # Cleanup retained messages from client.
    for top in ctx.retained:
      if mqttbroker.retained[top].clientid == ctx.clientid:
        mqttbroker.retained.del(top)

  if not ctx.s.isClosed() and ctx.beenConnected:
    ctx.s.close()
  ctx.state = Disabled

  if mqttbroker.verbosity >= 3:
    verbose(ctx)


proc serve(host: string, port: int) {.async.} =
  var broker = newAsyncSocket()
  broker.setSockOpt(OptReuseAddr, true)
  broker.bindAddr(Port(port), host)
  broker.listen()

  if mqttbroker.sslOn:
    if not fileExists(mqttbroker.sslCert) or not fileExists(mqttbroker.sslKey):
      echo "SSL cert or key does not exist. Check the path or generate them:\n" &
           "openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout mykey.pem -out mycert.pem"
    var sslCtx = newContext(certFile = mqttbroker.sslCert, keyFile = mqttbroker.sslKey)
    wrapSocket(sslCtx, broker)
    while true:
      let client = await broker.accept()
      wrapConnectedSocket(sslCtx, client, handshakeAsServer)
      asyncCheck processClient(client)

  else:
    while true:
      let client = await broker.accept()
      asyncCheck processClient(client)


proc showConf(mb: MqttBroker, configfile: string) =
  ## Show the config details

  echo """
Running nmqtt v$1

BROKER:
  Host:       $2
  Port:       $3
  SSL:        $4
  Starting:   $5

OPTIONS:
  Verbosity:             $6
  Max connections:       $7
  ClientID max lenght:   $8
  ClientID allow spaces: $9
  ClientID allow empty:  $10
  ClientID in payload:   $11
  Client kick old:       $12
  Number of passwords:   $13

  """.format(nmqttVersion, mb.host, mb.port, mb.sslOn, now(), mb.verbosity,
              mb.maxConnections, mb.clientIdMaxLen, mb.spacesInClientId,
              mb.emptyClientId, mb.passClientId, mb.clientKickOld, mb.passwords.len()
            )


  if configfile != "":
    echo """
CONFIG:
  Using configuration file:
  $1

  """.format(configfile)


proc loadPasswords(passwordFile: string) =
  ## Loads the usernames and passwords
  if passwordFile == "":
    echo "\nPath to password file is missing..\n"
    quit()
  elif not fileExists(passwordFile):
    echo "\nPassword file does not exists..\n - " & passwordFile
    quit()

  for line in readFile(passwordFile).split("\n"):
    let pass = split(line, ":", maxsplit=1)
    mqttbroker.passwords[pass[0]] = pass[1]


proc loadConf(mb: MqttBroker, config: string) =
  ## Parses the config file

  if not fileExists(config):
    echo "\nConfiguration files does not exists.."
    quit()

  let dict = loadConfig(config)
  mqttbroker.version          = 4
  mqttbroker.host             = dict.getSectionValue("","host")
  mqttbroker.port             = Port(parseInt(dict.getSectionValue("","port")))
  mqttbroker.verbosity        = parseInt(dict.getSectionValue("","verbosity"))
  mqttbroker.clientIdMaxLen   = parseInt(dict.getSectionValue("","clientid_maxlen"))
  mqttbroker.spacesInClientId = parseBool(dict.getSectionValue("","clientid_spaces"))
  mqttbroker.emptyClientId    = parseBool(dict.getSectionValue("","clientid_empty"))
  mqttbroker.passClientId     = parseBool(dict.getSectionValue("","clientid_pass"))
  mqttbroker.clientKickOld    = parseBool(dict.getSectionValue("","client_kickold"))
  mqttbroker.maxConnections   = parseInt(dict.getSectionValue("","max_conn"))
  mqttbroker.sslCert          = dict.getSectionValue("","ssl_certificate")
  mqttbroker.sslKey           = dict.getSectionValue("","ssl_key")

  # If both certificate and key are present use SSL.
  if mqttbroker.sslCert != "" and mqttbroker.sslKey != "":
    mqttbroker.sslOn = true

  # If anonymous login is allowed return
  if not parseBool(dict.getSectionValue("","allow_anonymous")):

    # Is password is required parse the password file
    let passwordFile = dict.getSectionValue("","password_file")
    loadPasswords(passwordFile)


proc handler() {.noconv.} =
  ## Catch ctrl+c from user
  echo " "
  if mqttbroker.verbosity >= 3:
    verbose(mqttbroker)
  quit()


proc nmqttBroker(config="", host="127.0.0.1", port=1883, verbosity=0, max_conn=0,
                  clientid_maxlen=60, clientid_spaces=false, clientid_empty=false,
                  client_kickold=false, clientid_pass=false, password_file="",
                  ssl=false, ssl_cert="", ssl_key=""
                ) {.async.} =
  ## CLI tool for a MQTT broker
  if config != "":
    loadConf(mqttbroker, config)
  else:
    mqttbroker.version          = 4
    mqttbroker.host             = host
    mqttbroker.port             = Port(port)
    mqttbroker.verbosity        = verbosity
    mqttbroker.clientIdMaxLen   = clientid_maxlen
    mqttbroker.spacesInClientId = clientid_spaces
    mqttbroker.emptyClientId    = clientid_empty
    mqttbroker.clientKickOld    = client_kickold
    mqttbroker.passClientId     = clientid_pass
    mqttbroker.maxConnections   = max_conn

    if password_file != "":
      loadPasswords(password_file)

    if ssl:
      mqttbroker.sslOn   = true
      mqttbroker.sslCert = ssl_cert
      mqttbroker.sslKey  = ssl_key

  if mqttbroker.verbosity >= 1:
    showConf(mqttbroker, config)

  asyncCheck serve(host, port)

  setControlCHook(handler)

  runForever()



when isMainModule:

  let topLvlUse = """nmqtt version """ & nmqttVersion & """


nmqtt is a MQTT v3.1.1 broker

USAGE
  $command [options]
  $command [-c /path/to/config.conf]
  $command [-h hostIP -p port]

CONFIG
  Use the configuration file for detailed settings,
  such as SSL, adjusting keep alive timer, etc. or
  specify options at the command line.

  To add and delete users from the password file
  please use nmqtt_password:
    - nmqtt_password -a|-b|-d [options]

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDescrip]

  dispatchGen(nmqttBroker,
          cmdName="nmqtt",
          help={
            "config":           "absolute path to the config file. Overrides all other options.",
            "host":             "IP-address to serve the broker on.",
            "port":             "network port to accept connecting from.",
            "verbosity":        "verbosity from 0-3.",
            "max-conn":         "max simultaneous connections. Defaults to no limit.",
            "clientid-maxlen":  "max lenght of clientid. Defaults to 65535.",
            "clientid-spaces":  "allow spaces in clientid. Defaults to false.",
            "clientid-empty":   "allow empty clientid and assign random id. Defaults to false.",
            "client-kickold":   "kick old client, if new client has same clientid. Defaults to false.",
            "clientid-pass":    "pass clientid in payload {clientid:payload}. Defaults to false.",
            "password-file":    "absolute path to the password file",
            "ssl":              "activate ssl for the broker - requires --ssl-cert and --ssl-key.",
            "ssl-cert":         "absolute path to the ssl certificate.",
            "ssl-key":          "absolute path to the ssl key."
          },
          short={
            "help": '?',
            "max-conn": '\0',
            "ssl": '\0',
            "ssl-cert": '\0',
            "ssl-key": '\0'
          },
          usage=topLvlUse,
          dispatchName="brokerCli"
          )

  cligenQuit brokerCli(skipHelp=true)