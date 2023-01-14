## Native Nim MQTT client library and binaries
##
## zevv (https://github.com/zevv) & ThomasTJdev (https://github.com/ThomasTJdev)

import
  strutils,
  asyncnet,
  net,
  asyncDispatch,
  tables

when defined(broker):
  import
    cligen,
    sequtils,
    times,
    random,
    nmqtt/utils/passwords,
    nmqtt/utils/version
  from parsecfg import loadConfig, getSectionValue
  from os import fileExists

type
  MqttCtx* = ref object
    host: string
    port: Port
    sslOn: bool
    sslCert: string
    sslKey: string
    verbosity: int
    beenConnected: bool
    username: string
    password: string
    state: State
    clientId: string
    s: AsyncSocket
    ssl: SslContext
    msgIdSeq: MsgId
    workQueue: Table[MsgId, Work]
    pubCallbacks: Table[string, PubCallback]
    inWork: bool
    keepAlive: uint16
    willFlag: bool
    willQoS: uint8
    willRetain: bool
    willTopic: string
    willMsg: string

    #when defined(broker):
    proto: string
    version: uint8
    connFlags: string
    retained: seq[string]
    subscribed: Table[string, uint8] # Topic, Qos
    lastAction: float # Check keepAlive

  #when defined(broker):
  ConnAckFlag = enum
    ConnAcc               = 0x00
    ConnRefProtocol       = 0x01
    ConnRefRejected       = 0x02
    ConnRefUnavailable    = 0x03
    ConnRefBadUserPwd     = 0x04
    ConnRefNotAuthorized  = 0x05

  State = enum
    Disabled, Disconnected, Connecting, Connected, Disconnecting, Error

  MsgId = uint16

  Qos = range[0..2]

  PktType = enum
    Notype      =  0
    Connect     =  1
    ConnAck     =  2
    Publish     =  3
    PubAck      =  4
    PubRec      =  5
    PubRel      =  6
    PubComp     =  7
    Subscribe   =  8
    SubAck      =  9
    Unsubscribe = 10
    Unsuback    = 11
    PingReq     = 12
    PingResp    = 13
    Disconnect  = 14

  ConnectFlag = enum
    WillQoS0     = 0x00
    CleanSession = 0x02
    WillFlag     = 0x04
    WillQoS1     = 0x08
    WillQoS2     = 0x10
    WillRetain   = 0x20
    PasswordFlag = 0x40
    UserNameFlag = 0x80

  Pkt = object
    typ: PktType
    flags: uint8
    data: seq[uint8]

  WorkKind = enum
    PubWork, SubWork

  WorkState = enum
    WorkNew, WorkSent, WorkAcked

  PubCallback = object
    cb: proc(topic: string, message: string)
    qos: int

  Work = ref object
    state: WorkState
    msgId: MsgId
    topic: string
    qos: Qos
    typ: PktType
    flags: uint16 #when defined(broker)
    case wk: WorkKind
    of PubWork:
      retain: bool
      message: string
    of SubWork:
      discard


when defined(broker):
  type
    MqttSub* = ref object ## Managing the subscribers
      subscribers: Table[string, seq[MqttCtx]]

    MqttBroker* = ref object
      host: string
      port: Port
      sslOn: bool
      sslCert: string
      sslKey: string
      verbosity: int
      connections: Table[string, MqttCtx]
      retained: Table[string, RetainedMsg] # Topic, RetaindMsg
      subscribers: Table[string, seq[MqttCtx]]
      version: uint8
      clientIdMaxLen: int
      clientKickOld: bool
      emptyClientId: bool
      spacesInClientId: bool
      passClientId: bool
      maxConnections: int
      passwords: Table[string, string]

    RetainedMsg = object
      msg: string
      qos: uint8
      time: float
      clientid: string

when defined(broker):
  var
    mqttbroker = MqttBroker()
    r = initRand(toInt(epochTime()))


#
# Packet helpers
#

proc put(pkt: var Pkt, v: uint16) =
  pkt.data.add (v.int /%  256).uint8
  pkt.data.add (v.int mod 256).uint8

proc put(pkt: var Pkt, v: uint8) =
  pkt.data.add v

proc put(pkt: var Pkt, data: string, withLen: bool) =
  if withLen:
    pkt.put data.len.uint16
  for c in data:
    pkt.put c.uint8

proc getu8(pkt: Pkt, offset: int): (uint8, int) =
  let val = pkt.data[offset]
  result = (val, offset+1)

proc getu16(pkt: Pkt, offset: int): (uint16, int) =
  let val = (pkt.data[offset].int*256 + pkt.data[offset+1].int).uint16
  result = (val, offset+2)

proc getstring(pkt: Pkt, offset: int, withLen: bool): (string, int) =
  var val: string
  if withLen:
    var (len, offset2) = pkt.getu16(offset)
    for i in 0..<len.int:
      val.add pkt.data[offset+i+2].char
    result = (val, offset2+len.int)
  else:
    for i in offset..<pkt.data.len:
      val.add pkt.data[i].char
    result = (val, pkt.data.len)

when defined(broker):
  proc getstring(pkt: Pkt, offset: int, len: int): (string, int) =
    var val: string
    for i in offset..<len+offset:
      val.add pkt.data[i].char
    result = (val, len+offset)

when defined(broker):
  proc getbin(pkt: Pkt, b: int): (string, int) =
    result = (toBin(parseBiggestInt($pkt.data[b]), 8), b+1)

proc `$`(pkt: Pkt): string =
  result.add $pkt.typ & "(" & $pkt.flags.toHex & "): "
  for b in pkt.data:
    result.add b.toHex
    result.add " "

proc newPkt(typ: PktType=NOTYPE, flags: uint8=0): Pkt =
  result.typ = typ
  result.flags = flags

#
# Debug
#
proc dmp(ctx: MqttCtx, s: string) =
  when not defined(broker):
    if defined(dev) or ctx.verbosity >= 2:
      stderr.write "\e[1;30m" & s & "\e[0m\n"
  when defined(broker):
    if defined(dev) or mqttbroker.verbosity >= 2:
      stderr.write "\e[1;30m" & s & "\e[0m\n"
  when defined(test):
    let s = split(s, " ")
    testDmp.add(@[$(s[0] & " " & s[1]), $join(s[2..s.len-1], " ")])

proc dbg(ctx: MqttCtx, s: string) =
  stderr.write "\e[37m" & s & "\e[0m\n"

proc verbose(s: string) =
  stderr.write "\e[37m" & s & "\e[0m\n"

when defined(broker):
  proc verbose(e: string, s: Table) =
    var output: string
    for t, c in s:
      if output != "":
        output.add(", ")
      when c is RetainedMsg:
        output.add("{" & t & "}")
      else:
        output.add("{" & t & ": " & $c.len & "}")
    stderr.write "\e[37m" & e & " >> " & output & "\e[0m\n"

  proc verbose(ctx: auto) =
    var output: string
    for t, c in fieldPairs(ctx[]):
      when c is AsyncSocket:
        let conn = if c.isClosed(): "..disconnected.." else: "..connected.."
        output.add("  " & t & ": " & conn & "\n")
      when c is Table:
        output.add("  " & t & ": " & $c.len & "\n")
      when c is MqttCtx:
        output.add("  " & t & ": " & $c.clientid & "\n")
      when c is string or c is bool or c is int or c is uint8 or c is uint16:
        output.add("  " & t & ": " & $c & "\n")

    when ctx is MqttBroker:
      stderr.write "\e[37m" & "Broker      >>\n" & output & "\e[0m\n"
    when ctx is MqttCtx:
      stderr.write "\e[37m" & "Client      >> " & ctx.clientid & "\n" & output & "\e[0m\n"

proc wrn(ctx: MqttCtx, s: string) =
  stderr.write "\e[1;31mWarning >> " & s & "\e[0m\n"

proc wrn(s: string) =
  stderr.write "\e[1;31mWarning >> " & s & "\e[0m\n"

#
# Subscribers
#

when defined(broker):
  proc addSubscriber*(ctx: MqttCtx, topic: string) {.async.} =
    ## Adds a subscriber to MqttBroker
    try:
      if mqttbroker.subscribers.hasKey(topic):
        mqttbroker.subscribers[topic].insert(ctx)
      else:
        mqttbroker.subscribers[topic] = @[ctx]
    except:
      wrn("Crash when adding a new subcriber")

when defined(broker):
  proc removeSubscriber*(ctx: MqttCtx, topic: string) {.async.} =
    ## Removes a subscriber from specific topic
    try:
      if mqttbroker.subscribers.hasKey(topic):
        mqttbroker.subscribers[topic] = filter(mqttbroker.subscribers[topic], proc(x: MqttCtx): bool = x != ctx)
    except:
      wrn("Crash when removing subscriber with specific topic")

when defined(broker):
  proc removeSubscriber*(ctx: MqttCtx) {.async.} =
    ## Removes a subscriber without knowing the topics
    var delTop: seq[string]
    for t, c in mqttbroker.subscribers:
      if ctx in c:
        mqttbroker.subscribers[t] = filter(c, proc(x: MqttCtx): bool = x != ctx)

        if mqttbroker.subscribers[t].len() == 0:
          delTop.add(t)

    for t in delTop:
      mqttbroker.subscribers.del(t)

when defined(broker):
  proc qosAlign(qP, qS: uint8): uint8 =
    ## Aligns the QOS for publisher and subscriber.
    if qP == qS:
      result = qP
    elif qP > qS:
      result = qS
    else:
      result = qP

when defined(broker):
  proc keepAliveMonitor(ctx: MqttCtx) {.async.}

#
# MQTT context
#

proc nextMsgId(ctx: MqttCtx): MsgId =
  inc ctx.msgIdSeq
  return ctx.msgIdSeq


proc sendDisconnect(ctx: MqttCtx): Future[bool] {.async.}


proc close(ctx: MqttCtx, reason: string) {.async.} =
  if ctx.state in {Connecting, Connected}:
    ctx.state = Disconnecting
    if ctx.verbosity >= 1:
      ctx.dbg "Closing: " & reason
    discard await ctx.sendDisconnect()
    ctx.s.close()
    ctx.state = Disconnected


proc send(ctx: MqttCtx, pkt: Pkt): Future[bool] {.async.} =
  ## Send the packet
  if ctx.state notin {Connecting, Connected, Disconnecting}:
    return false

  var hdr: seq[uint8]
  hdr.add (pkt.typ.int shl 4).uint8 or pkt.flags

  var len = pkt.data.len
  while true:
    var b = len mod 128
    len = len div 128
    if len > 0:
      b = b or 128
    hdr.add b.uint8
    if len == 0:
      break

  ctx.dmp "tx> " & $pkt
  await ctx.s.send(hdr[0].unsafeAddr, hdr.len)

  if pkt.data.len > 0:
    await ctx.s.send(pkt.data[0].unsafeAddr, pkt.data.len)

  return true


proc recv(ctx: MqttCtx): Future[Pkt] {.async.} =
  ## Receive and parse the packet
  if ctx.state notin {Connecting,Connected}:
    return

  var r: int
  var b: uint8

  # TODO:
  # When the broker is running in SSL-mode, we need the try/except, since
  # we will encounter a silent crash in recvInto, when the client is
  # not actually using SSL.
  try:
    r = await ctx.s.recvInto(b.addr, b.sizeof)
  except:
    return
  if r != 1:
    when not defined(broker):
      await ctx.close("remote closed connection")
    return

  let typ = (b shr 4).PktType
  let flags = (b and 0x0f)
  var pkt = newPkt(typ, flags)

  var len: int
  var mul = 1
  for i in 0..3:
    var b: uint8
    r = await ctx.s.recvInto(b.addr, b.sizeof)

    if r != 1:
      when not defined(broker):
        await ctx.close("remote closed connection")
      return

    assert r == 1
    inc len, (b and 127).int * mul
    mul *= 128
    if ((b.int) and 0x80) == 0:
      break

  if len > 0:
    pkt.data.setlen len
    r = await ctx.s.recvInto(pkt.data[0].addr, len)

    if r != len:
      when not defined(broker):
        await ctx.close("remote closed connection")
      return

  ctx.dmp "rx> " & $pkt
  return pkt


proc sendConnect(ctx: MqttCtx): Future[bool] =
  var flags: uint8
  flags = flags or CleanSession.uint8
  if ctx.willFlag:
    flags = flags or WillFlag.uint8
    if ctx.willQoS == 1:
      flags = flags or WillQoS1.uint8
    elif ctx.willQoS == 2:
      flags = flags or WillQoS2.uint8
    if ctx.willRetain:
      flags = flags or WillRetain.uint8

  if ctx.username != "":
    flags = flags or UserNameFlag.uint8
  if ctx.password != "":
    flags = flags or PasswordFlag.uint8

  var pkt = newPkt(Connect)
  pkt.put "MQTT", true
  pkt.put 4.uint8
  pkt.put flags
  pkt.put ctx.keepAlive.uint16
  pkt.put ctx.clientId, true

  if ctx.willFlag:
    pkt.put (ctx.willTopic.len).uint16
    pkt.put ctx.willTopic, false
    pkt.put (ctx.willMsg.len).uint16
    pkt.put ctx.willMsg, false
  if ctx.username != "":
    pkt.put ctx.username, true
  if ctx.password != "":
    pkt.put ctx.password, true
  ctx.state = Connecting
  result = ctx.send(pkt)


proc sendDisconnect(ctx: MqttCtx): Future[bool] =
  let pkt = newPkt(Disconnect, 0)
  result = ctx.send(pkt)

proc sendSubscribe(ctx: MqttCtx, msgId: MsgId, topic: string, qos: Qos): Future[bool] =
  var pkt = newPkt(Subscribe, 0b0010)
  pkt.put msgId.uint16
  pkt.put topic, true
  pkt.put qos.uint8
  result = ctx.send(pkt)

proc sendUnsubscribe(ctx: MqttCtx, msgId: MsgId, topic: string): Future[bool] =
  var pkt = newPkt(Unsubscribe, 0b0010)
  pkt.put msgId.uint16
  pkt.put topic, true
  result = ctx.send(pkt)

proc sendPublish(ctx: MqttCtx, msgId: MsgId, topic: string, message: string, qos: Qos, retain: bool): Future[bool] =
  var flags = (qos shl 1).uint8
  if retain:
    flags = flags or 1
  var pkt = newPkt(Publish, flags)
  pkt.put topic, true
  if qos > 0:
    pkt.put msgId.uint16
  pkt.put message, false
  result = ctx.send(pkt)

proc sendPubAck(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(PubAck, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

proc sendPubRec(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(PubRec, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

proc sendPubRel(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(PubRel, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

proc sendPubComp(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(PubComp, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

proc sendPingReq(ctx: MqttCtx): Future[bool] =
  var pkt = newPkt(Pingreq)
  result = ctx.send(pkt)

#when defined(broker):
proc sendConnAck(ctx: MqttCtx, flags: uint16): Future[bool] =
  var pkt = newPkt(ConnAck)
  pkt.put flags.uint16
  result = ctx.send(pkt)

#when defined(broker):
proc sendSubAck(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(SubAck, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

#when defined(broker):
proc sendUnsubAck(ctx: MqttCtx, msgId: MsgId): Future[bool] =
  var pkt = newPkt(Unsuback, 0b0010)
  pkt.put msgId.uint16
  result = ctx.send(pkt)

#when defined(broker):
proc sendPingResp(ctx: MqttCtx): Future[bool] =
  var pkt = newPkt(PingResp)
  result = ctx.send(pkt)

proc sendWork(ctx: MqttCtx, work: Work): Future[bool] =
  case work.typ
  of Publish:   # Publish
    result = ctx.sendPublish(work.msgId, work.topic, work.message, work.qos, work.retain)

  of PubRel:    # Publish qos=2 (activated from a PubRec)
    result = ctx.sendPubRel(work.msgId)

  of PubAck:    # Subscribe qos=1 (activated from a Publish)
    result = ctx.sendPubAck(work.msgId)

  of PubRec:    # Subscribe qos=2 (1/2) (activated from a Publish)
    result = ctx.sendPubRec(work.msgId)

  of PubComp:   # Subscribe qos=2 (2/2) (activated from a PubRel)
    result = ctx.sendPubComp(work.msgId)

  of Subscribe:
    result = ctx.sendSubscribe(work.msgId, work.topic, work.qos)

  of Unsubscribe:
    result = ctx.sendUnsubscribe(work.msgId, work.topic)

  of ConnAck:
    #when defined(broker):
    result = ctx.sendConnAck(work.flags)

  of PingResp:
    #when defined(broker):
    result = ctx.sendPingResp()

  of SubAck:
    #when defined(broker):
    result = ctx.sendSubAck(work.msgId)

  of Unsuback:
    #when defined(broker):
    result = ctx.sendUnsubAck(work.msgId)

  else:
    ctx.wrn("Error sending unknown package: " & $work.typ)

proc work(ctx: MqttCtx) {.async.} =
  if ctx.inWork:
    return
  ctx.inWork = true
  if ctx.state == Connected:
    var delWork: seq[MsgId]
    let workQueue = ctx.workQueue # TODO: We need to copy the workQueue, otherwise
                                  # we can hit: `the length of the table changed
                                  # while iterating over it`
    for msgId, work in workQueue:

      #when defined(broker):
      if work.typ in [ConnAck, SubAck, UnsubAck, PingResp]:
        if await ctx.sendWork(work):
          delWork.add msgId
          continue

      if work.wk == PubWork and work.state == WorkNew:
        if work.typ == Publish and work.qos == 0:
          if await ctx.sendWork(work): delWork.add msgId

        elif work.typ == PubAck and work.qos == 1:
          if await ctx.sendWork(work): delWork.add msgId

        elif work.typ == PubComp and work.qos == 2:
          if await ctx.sendWork(work): delWork.add msgId

        else:
          if await ctx.sendWork(work): work.state = WorkSent

      #when not defined(broker):
      elif work.wk == SubWork and work.state == WorkNew:
        if work.typ == Subscribe:
          if await ctx.sendWork(work): work.state = WorkSent

        elif work.typ == Unsubscribe:
          if await ctx.sendWork(work):
            work.state = WorkSent
            ctx.pubCallbacks.del work.topic

    for msgId in delWork:
      ctx.workQueue.del msgId
  ctx.inWork = false

when defined(broker):
  proc sendWill(ctx: MqttCtx) {.async.} =
    ## Send the will
    if ctx.willTopic != "":
      for c in mqttbroker.subscribers[ctx.willTopic]:
        let msgId = c.nextMsgId()
        let qos = qosAlign(ctx.willQos, c.subscribed[ctx.willTopic])
        c.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: ctx.willTopic, qos: qos, message: ctx.willMsg, typ: Publish)
        await c.work()

when defined(broker):
  proc publishToSubscribers(seqctx: seq[MqttCtx], pkt: Pkt, topic, message: string, qos: uint8, retain: bool, senderId: string) {.async.} =
    ## Publish async to clients
    for c in seqctx:
      if c.state != Connected:
        asyncCheck removeSubscriber(c, topic)
        continue
      let
        msgId = c.nextMsgId()
        qosSub = qosAlign(qos, c.subscribed[topic])

      if mqttbroker.passClientId:
        c.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, qos: qosSub, retain: retain, message: senderId & ":" & message, typ: Publish)
      else:
        c.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, qos: qosSub, retain: retain, message: message, typ: Publish)
      await c.work()

when defined(broker):
  proc denyConnect(ctx: MqttCtx, connFlag: ConnAckFlag) {.async.} =
    ## Denying connections and closing socket
    discard await sendConnAck(ctx, connFlag.uint16)
    ctx.state = Disabled # [MQTT-3.2.2-5] Close the connection immediately
    ctx.s.close()

#when defined(broker):
proc onConnect(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when not defined(broker):
    ctx.wrn "Packet type only supported for broker: " & $pkt.typ
  else:
    var
      offset: int
      nextLen: uint16

    # Main data
    (ctx.proto, offset)     = pkt.getstring(0, true)
    (ctx.version, offset)   = pkt.getu8(offset)
    (ctx.connFlags, offset) = getbin(pkt, offset)
    (ctx.keepAlive, offset) = pkt.getu16(offset)
    (nextLen, offset)       = pkt.getu16(offset)
    (ctx.clientId, offset)  = pkt.getstring(offset, parseInt($nextLen))
    if not mqttbroker.spacesInClientId:
      ctx.clientid = ctx.clientid.replace(" ", "")

    # Will Topic
    if ctx.connFlags[5] == '1':
      (nextLen, offset)         = pkt.getu16(offset)
      (ctx.willTopic, offset)   = pkt.getstring(offset,  parseInt($nextLen))
      (nextLen, offset)         = pkt.getu16(offset)
      (ctx.willMsg, offset)     = pkt.getstring(offset,  parseInt($nextLen))

      # Will Retain
      if ctx.connFlags[2] == '1':
        ctx.willRetain = true

      # Will qos=2
      if ctx.connFlags[3] == '1':
        ctx.willQos = 2.uint8
      # Will qos=1
      elif ctx.connFlags[4] == '1':
        ctx.willQos = 1.uint8

    # Username
    if ctx.connFlags[0] == '1':
      (nextLen, offset)       = pkt.getu16(offset)
      (ctx.username, offset)  = pkt.getstring(offset,  parseInt($nextLen))

    # Password
    if ctx.connFlags[1] == '1':
      (nextLen, offset)      = pkt.getu16(offset)
      (ctx.password, offset) = pkt.getstring(offset,  parseInt($nextLen))

    # Check password and username
    if mqttbroker.passwords.len() > 0:
      let pass = mqttbroker.passwords.getOrDefault(ctx.username)
      when defined(Windows):
        ## TODO: Windows is using MD5 for storing the password, which is not
        ##       safe in any way.
        if pass == "" or pass[0..31] != makePassword(ctx.password, pass[32..pass.len-1], ""):
          await denyConnect(ctx, ConnRefBadUserPwd)
          return
      else:
        if pass == "" or pass[0..59] != makePassword(ctx.password, pass[60..pass.len-1], pass[0..59]):
          await denyConnect(ctx, ConnRefBadUserPwd)
          return

    # 3.1.2.2 Protocol Level
    if ctx.proto != "MQTT":
      await denyConnect(ctx, ConnRefProtocol)
      return

    # 3.1.2.2 Protocol Level
    if ctx.version != mqttbroker.version:
      await denyConnect(ctx, ConnRefProtocol)
      return

    # Check if clientid already exist as an connection.
    # Close connection if clientID is identical to existing clientID [MQTT-3.1.4-2]
    if mqttbroker.connections.hasKey(ctx.clientid):
      if mqttbroker.clientKickOld:
        mqttbroker.connections[ctx.clientid].state = Disabled
        mqttbroker.connections[ctx.clientid].s.close()
      else:
        await denyConnect(ctx, ConnRefRejected)
        return

    # Require a clientID [MQTT-3.1.3-5], [MQTT-3.1.3-8], [MQTT-3.1.3-9]
    if ctx.clientid.strip() == "":
      # [MQTT-3.1.3-6] Assign random unique key
      if mqttbroker.emptyClientId:
        ctx.clientid = $r.next()
      else:
        await denyConnect(ctx, ConnRefRejected)
        return

    # Check the lenght of the clientID
    if ctx.clientid.len() > mqttbroker.clientIdMaxLen:
      await denyConnect(ctx, ConnRefRejected)
      return

    # Check for max simultaneous connections
    if mqttbroker.maxConnections > 0 and mqttbroker.connections.len() == mqttbroker.maxConnections:
      await denyConnect(ctx, ConnRefUnavailable)
      return

    mqttbroker.connections[ctx.clientid] = ctx
    ctx.state = Connected
    ctx.beenConnected = true
    asyncCheck keepAliveMonitor(ctx)

    if mqttbroker.verbosity >= 1:
      verbose("Connections >> " & ctx.clientId & " has connected")
    if mqttbroker.verbosity >= 3:
      verbose(ctx)

    ctx.workQueue[0.uint16] = Work(wk: PubWork, flags: ConnAcc.uint16, state: WorkNew, qos: 0, typ: ConnAck)
    await ctx.work()

proc onConnAck(ctx: MqttCtx, pkt: Pkt): Future[void] =
  ctx.state = Connected
  let (code, _) = pkt.getu8(1)
  if code == 0:
    ctx.beenConnected = true
    if ctx.verbosity >= 1:
      ctx.dbg "Connection established"
  else:
    ctx.wrn "Connect failed, code: " & $code
  result = ctx.work()

proc onPublish(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let
    qos = (pkt.flags shr 1) and 0x03
    retain = if (pkt.flags and 0x01) == 1: true else: false
                                # When subscribing and first message is a
                                # retained message, this will be `1`
                                # otherwise `0`.
                                #
                                # TODO for nmqtt_sub:
                                # Allow for passing the retained flag, so
                                # the subscriber can decide, if it wants
                                # only reteained message with --retained-only flag.
  var
    offset: int
    msgid: MsgId
    topic, message: string
  (topic, offset) = pkt.getstring(0, true)
  if qos == 1 or qos == 2:
    (msgid, offset) = pkt.getu16(offset)
  (message, offset) = pkt.getstring(offset, false)

  when defined(broker):
    # Send message to all subscribers on "#"
    if mqttbroker.subscribers.hasKey("#"):
      await publishToSubscribers(mqttbroker.subscribers["#"], pkt, "#", message, qos, retain, ctx.clientid)
    # Send message to all subscribers on _the topic_
    if mqttbroker.subscribers.hasKey(topic):
      await publishToSubscribers(mqttbroker.subscribers[topic], pkt, topic, message, qos, retain, ctx.clientid)

    if mqttbroker.verbosity >= 1:
      verbose("Client      >> " & ctx.clientId & " has published a message")

    if retain:
      if qos == 0 and message == "":
        mqttbroker.retained.del(topic)
      else:
        # Add or overwrite existing retained messages on this topic.
        mqttbroker.retained[topic] = RetainedMsg(msg: message, qos: qos, time: epochTime(), clientid: ctx.clientid)
        # Check if client already has published a retained messaged on this topic. In that
        # case do not add it, since the QOS, msg and time is preserved in the MqttBroker.retained.
        if topic notin ctx.retained:
          ctx.retained.add(topic)

      if mqttbroker.verbosity >= 1:
        verbose("Retained   ", mqttbroker.retained)

  when not defined(broker):
    for top, cb in ctx.pubCallbacks:
      if top == topic or top == "#":
        cb.cb(topic, message)
      if top.endsWith("/#"):
        # the multi-level wildcard can represent zero levels.
        if topic == top[0 .. ^3]:
          cb.cb(topic, message)
          continue
        var topicw = top
        topicw.removeSuffix("#")
        if topic.contains(topicw):
          cb.cb(topic, message)
      if top.contains("+"):
        var topelem = split(top, '/')
        if len(topelem) == count(topic, '/') + 1:
          var i = 0
          for e in split(topic, '/'):
            if topelem[i] != "+" and e != topelem[i]: break
            i = i+1
          if i == len(topelem):
            cb.cb(topic, message)

  if qos == 1:
    ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 1, typ: PubAck)
    await ctx.work()
  elif qos == 2:
    ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 2, typ: PubRec)
    await ctx.work()

proc onPubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 1
  ctx.workQueue.del msgId

proc onPubRec(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 2
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 2, typ: PubRel)
  await ctx.work()

proc onPubRel(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 2
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 2, typ: PubComp)
  await ctx.work()

proc onPubComp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 2
  ctx.workQueue.del msgId

#when defined(broker):
proc onSubscribe(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when not defined(broker):
    ctx.wrn "Packet type only supported for broker: " & $pkt.typ
  else:
    var
      offset: int
      msgId: MsgId
      topic: string
      qos: uint8
      nextLen: uint16

    (msgId, offset) = pkt.getu16(0)
    ctx.msgIdSeq    = msgId

    while offset < pkt.data.len:
      (nextLen, offset) = pkt.getu16(offset)
      (topic, offset)   = pkt.getstring(offset, parseInt($nextLen))
      (qos, offset)     = pkt.getu8(offset)

      ctx.subscribed[topic] = qos
      await addSubscriber(ctx, topic)

    ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 0, typ: SubAck)

    # Send retained messaged for #
    if topic == "#":
      for top, ret in mqttbroker.retained:
        let
          msgId = ctx.nextMsgId()
          qosRet = qosAlign(qos, ret.qos)
        ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: top, qos: qosRet, message: ret.msg, typ: Publish)
    # Send retained messaged for specific topic
    elif mqttbroker.retained.hasKey(topic):
      let
        msgId = ctx.nextMsgId()
        qosRet = qosAlign(qos, mqttbroker.retained[topic].qos)
      ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, qos: qosRet, message: mqttbroker.retained[topic].msg, typ: Publish)

    if mqttbroker.verbosity >= 1:
      verbose("Client      >> " & ctx.clientId & " has subscribed to a topic")
      verbose("Subscribers", mqttbroker.subscribers)

    await ctx.work()

proc onSubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  assert ctx.workQueue[msgId].state == WorkSent
  ctx.workQueue.del msgId

#when defined(broker):
proc onUnsubscribe(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when not defined(broker):
    ctx.wrn "Packet type only supported for broker: " & $pkt.typ
  else:
    var
      offset: int
      msgId: MsgId
      topic: string
      nextLen: uint16

    (msgId, offset) = pkt.getu16(0)
    ctx.msgIdSeq    = msgId

    while offset < pkt.data.len:
      (nextLen, offset) = pkt.getu16(offset)
      (topic, offset)   = pkt.getstring(offset, parseInt($nextLen))

      await removeSubscriber(ctx, topic)
      ctx.subscribed.del(topic)

    if mqttbroker.verbosity >= 1:
      verbose("Client      >> " & ctx.clientId & " has unsubscribed from a topic")
      verbose("Subscribers", mqttbroker.subscribers)

    ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 0, typ: UnsubAck)
    await ctx.work()

proc onUnsubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  assert ctx.workQueue[msgId].state == WorkSent
  ctx.workQueue.del msgId

#when defined(broker):
proc onDisconnect(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when not defined(broker):
    ctx.wrn "Packet type only supported for broker: " & $pkt.typ
  else:
    #await removeSubscriber(ctx)
    #await sendWill(ctx)
    ctx.state = Disconnected
    if mqttbroker.verbosity >= 1:
      verbose("Connections >> " & ctx.clientid & " has disconnected")

#when defined(broker):
proc onPingReq(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when not defined(broker):
    ctx.wrn "Packet type only supported for broker: " & $pkt.typ
  else:
    var msgId = ctx.nextMsgId() + 1000
    while ctx.workQueue.hasKey(msgId):
      msgId += 1000
    ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, state: WorkNew, qos: 0, typ: PingResp)
    await ctx.work()

proc onPingResp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  discard

proc handle(ctx: MqttCtx, pkt: Pkt) {.async.} =
  when defined(broker):
    ctx.lastAction = epochTime()

  case pkt.typ
    of ConnAck: await ctx.onConnAck(pkt)
    of Publish: await ctx.onPublish(pkt)
    of PubAck: await ctx.onPubAck(pkt)
    of PubRec: await ctx.onPubRec(pkt)
    of PubRel: await ctx.onPubRel(pkt)
    of PubComp: await ctx.onPubComp(pkt)
    of SubAck: await ctx.onSubAck(pkt)
    of UnsubAck: await ctx.onUnsubAck(pkt)
    of PingResp: await ctx.onPingResp(pkt)
    #when defined(broker):
    of Connect: await ctx.onConnect(pkt)
    of Subscribe: await ctx.onSubscribe(pkt)
    of Unsubscribe: await ctx.onUnsubscribe(pkt)
    of Disconnect: await ctx.onDisconnect(pkt)
    of PingReq: await ctx.onPingReq(pkt)
    else: ctx.wrn "Unknown pkt type " & $pkt.typ

#
# Async work functions
#

proc runRx(ctx: MqttCtx) {.async.} =
  try:
    while true:
      var pkt = await ctx.recv()
      if pkt.typ == Notype:
        break
      await ctx.handle(pkt)
  except OsError:
    if ctx.verbosity >= 2:
      ctx.wrn "Boom, socket is closed"

proc runPing(ctx: MqttCtx) {.async.} =
  while true:
    await sleepAsync ctx.keepAlive.int * 1000
    let ok = await ctx.sendPingReq()
    if not ok:
      break
    await ctx.work()

proc connectBroker(ctx: MqttCtx) {.async.} =
  ## Connect to the broker
  if ctx.keepAlive == 0:
    ctx.keepAlive = 60

  if ctx.verbosity >= 1:
    ctx.dbg "Connecting to " & ctx.host & ":" & $ctx.port
  try:
    ctx.s = await asyncnet.dial(ctx.host, ctx.port)
    if ctx.sslOn:
      when defined(ssl):
        ctx.ssl = newContext(protSSLv23, CVerifyNone, ctx.sslCert, ctx.sslKey)
        wrapConnectedSocket(ctx.ssl, ctx.s, handshakeAsClient)
      else:
        ctx.wrn "Requested SSL session but ssl is not enabled"
        await ctx.close("SSL not enabled")
        ctx.state = Error
    let ok = await ctx.sendConnect()
    if ok:
      asyncCheck ctx.runRx()
      asyncCheck ctx.runPing()
  except OSError as e:
    if ctx.verbosity >= 1 or not ctx.beenConnected:
      ctx.dbg "Error connecting to " & ctx.host
    if ctx.verbosity >= 2:
      echo e.msg
    ctx.state = Error

proc runConnect(ctx: MqttCtx) {.async.} =
  ## Auto-connect and reconnect to broker
  await ctx.connectBroker()

  while true:
    if ctx.state == Disabled:
      break
    elif ctx.state in [Disconnected, Error]:
      await ctx.connectBroker()
      # If the client has been disconnect, it is necessary to tell the broker,
      # that we still want to be Subscribed. PubCallbacks still holds the
      # callbacks, but we need to re-Subscribe to the broker.
      #
      # If we Publish during the Disconnected, the msg will not be send, cause
      # work() checks that `state=Connected`. Therefor our re-Subscribe
      # will be inserted first in the queue.
      if ctx.workQueue.len() == 0:
        for topic, cb in ctx.pubCallbacks:
          let msgId = ctx.nextMsgId()
          ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, qos: cb.qos, typ: Subscribe)
    await sleepAsync 1000

#
# Public API
#

proc newMqttCtx*(clientId: string): MqttCtx =
  ## Initiate a new MQTT client
  MqttCtx(clientId: clientId)

proc set_ping_interval*(ctx: MqttCtx, txInterval: int = 60) =
  ## Set the clients ping interval in seconds. Default is 60 seconds.
  if txInterval > 0 and txInterval < 65535:
    ctx.keepAlive = txInterval.uint16

proc set_host*(ctx: MqttCtx, host: string, port: int=1883, sslOn=false) =
  ## Set the MQTT host
  ctx.host = host
  ctx.port = Port(port)
  ctx.sslOn = sslOn

proc set_ssl_certificates*(ctx: MqttCtx, sslCert: string, sslKey: string) =
  # Sets the SSL Certificate and Key to use when connecting to the remote broker
  # for mutal TLS authentication
  ctx.sslCert = sslCert
  ctx.sslKey = sslKey

proc set_auth*(ctx: MqttCtx, username: string, password: string) =
  ## Set the authentication for the host.
  ctx.username = username
  ctx.password = password

proc set_will*(ctx: MqttCtx, topic, msg: string, qos=0, retain=false) =
  ## Set the clients will.
  ctx.willFlag   = true
  ctx.willTopic  = topic
  ctx.willMsg    = msg
  ctx.willQoS    = qos.uint8
  ctx.willRetain = retain

proc set_verbosity*(ctx: MqttCtx, verbosity: int) =
  ## Set the verbosity.
  ctx.verbosity = verbosity

proc connect*(ctx: MqttCtx) {.async.} =
  ## Connect to the broker.
  await ctx.connectBroker()

proc start*(ctx: MqttCtx) {.async.} =
  ## Auto-connect and reconnect to the broker. The client will try to
  ## reconnect when the state is `Disconnected` or `Error`. The `Error`-state
  ## happens, when the broker is down, but the client will try to reconnect
  ## until the broker is up again.
  ctx.state = Disconnected
  asyncCheck ctx.runConnect()

proc disconnect*(ctx: MqttCtx) {.async.} =
  ## Disconnect from the broker.
  await ctx.close("disconnect")
  ctx.state = Disabled

proc publish*(ctx: MqttCtx, topic: string, message: string, qos=0, retain=false) {.async.} =
  ## Publish a message.
  ##
  ## **Required:**
  ##  - topic: string
  ##  - message: string
  ##
  ## **Optional:**
  ##  - qos: int     = 0, 1 or 2
  ##  - retain: bool = true or false
  ##
  ##
  ## **Publish message:**
  ## .. code-block::nim
  ##    ctx.publish(topic = "nmqtt", message = "Hey there", qos = 0, retain = true)
  ##
  ##
  ## **Remove retained message on topic:**
  ##
  ## Set the `message` to _null_.
  ## .. code-block::nim
  ##    ctx.publish(topic = "nmqtt", message = "", qos = 0, retain = true)
  ##
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, qos: qos, message: message, retain: retain, typ: Publish)
  await ctx.work()

proc subscribe*(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback.cb): Future[void] =
  ## Subscribe to a topic.
  ##
  ## Access the callback with:
  ## .. code-block::nim
  ##    proc callbackName(topic: string, message: string) =
  ##      echo "Topic: ", topic, ": ", message
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, qos: qos, typ: Subscribe)
  ctx.pubCallbacks[topic] = PubCallback(cb: callback, qos: qos)
  result = ctx.work()

proc unsubscribe*(ctx: MqttCtx, topic: string): Future[void] =
  ## Unsubscribe to a topic.
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, typ: Unsubscribe)
  result = ctx.work()

proc isConnected*(ctx: MqttCtx): bool =
  ## Returns true, if the client is connected to the broker.
  if ctx.state == Connected:
    result = true

proc msgQueue*(ctx: MqttCtx): int =
  ## Returns the number of unfinished packages, which still are in the work queue.
  ## This includes all publish and subscribe packages, which has not been fully
  ## send, acknowledged or completed.
  ##
  ## You can use this to ensure, that all your of messages are sent, before
  ## exiting your program.
  result = ctx.workQueue.len()
