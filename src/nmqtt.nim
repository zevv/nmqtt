## Native Nim MQTT client library, work in progress
## ---------------
##
## Examples
## --------
##
## All in one
## .. code-block::plain
##    import nmqtt, asyncdispatch
##
##    let ctx = newMqttCtx("hallo")
##
##    ctx.set_host("test.mosquitto.org", 1883)
##    #ctx.set_auth("username", "password")
##
##    await ctx.start()
##    proc on_data(topic: string, message: string) =
##      echo "got ", topic, ": ", message
##
##    await ctx.subscribe("#", 2, on_data)
##    await ctx.publish("test1", "hallo", 2)
##
##    asyncCheck flop()
##    runForever()
##
## Individual
## .. code-block::plain
##    import nmqtt, asyncdispatch
##
##    let ctx = newMqttCtx("hallo")
##    ctx.set_host("test.mosquitto.org", 1883)
##    #ctx.set_auth("username", "password")
##    await ctx.start()
##
##    proc mqttSub() {.async.} =
##      await ctx.start()
##      proc on_data(topic: string, message: string) =
##        echo "got ", topic, ": ", message
##
##      await ctx.subscribe("#", 2, on_data)
##
##    proc mqttPub() {.async.} =
##      await ctx.start()
##      await ctx.publish("test1", "hallo", 2, waitConfirmation=true)
##      await ctx.disconnect()
##
##    proc mqttPubSleep() {.async.} =
##      await ctx.start()
##      await ctx.publish("test1", "hallo", 2)
##      await sleepAsync 5000
##      await ctx.disconnect()
##
##    #asyncCheck mqttSub
##    #runForever()
##    # OR
##    #waitFor mqttPub()
##    # OR
##    #waitFor mqttPubSleep()

#{.experimental: "codeReordering".}

import strutils
import asyncnet
import net
import asyncDispatch
import tables

type

  MqttCtx* = ref object
    host: string
    port: Port
    doSsl: bool
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
    pingTxInterval: int # ms

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

  PubState = enum
    PubNew, PubSent, PubAcked

  WorkKind = enum
    PubWork, SubWork

  WorkState = enum
    WorkNew, WorkSent, WorkAcked, WorkConfirm

  PubCallback = proc(topic: string, message: string)

  Work = ref object
    state: WorkState
    msgId: MsgId
    topic: string
    qos: Qos
    typ: PktType
    case wk: WorkKind
    of PubWork:
      retain: bool
      message: string
    of SubWork:
      discard

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

proc `$`(pkt: Pkt): string =
  result.add $pkt.typ & "(" & $pkt.flags.toHex & "): "
  for b in pkt.data:
    result.add b.toHex
    result.add " "

proc newPkt(typ: PktType=NOTYPE, flags: uint8=0): Pkt =
  result.typ = typ
  result.flags = flags

#
# MQTT context
#

proc dmp(ctx: MqttCtx, s: string) =
  when defined(dev):
    stderr.write "\e[1;30m" & s & "\e[0m\n"
  when defined(test):
    let s = split(s, " ")
    testDmp.add(@[$(s[0] & " " & s[1]), $join(s[2..s.len-1], " ")])

proc dbg(ctx: MqttCtx, s: string) =
  stderr.write "\e[37m" & s & "\e[0m\n"

proc wrn(ctx: MqttCtx, s: string) =
  stderr.write "\e[1;31m" & s & "\e[0m\n"

proc nextMsgId(ctx: MqttCtx): MsgId =
  inc ctx.msgIdSeq
  return ctx.msgIdSeq

proc sendDisconnect(ctx: MqttCtx): Future[bool] {.async.}


proc close(ctx: MqttCtx, reason: string) {.async.} =
  if ctx.state in {Connecting, Connected}:
    ctx.state = Disconnecting
    ctx.dbg "Closing: " & reason
    discard await ctx.sendDisconnect()
    ctx.s.close()
    ctx.state = Disconnected


proc send(ctx: MqttCtx, pkt: Pkt): Future[bool] {.async.} =

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

  if ctx.state notin {Connecting,Connected}:
    return

  var r: int
  var b: uint8
  r = await ctx.s.recvInto(b.addr, b.sizeof)
  if r != 1:
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
      await ctx.close("remote closed connection")
      return

  ctx.dmp "rx> " & $pkt
  return pkt


proc sendConnect(ctx: MqttCtx): Future[bool] =
  var flags: uint8
  flags = flags or CleanSession.uint8
  if ctx.username != "":
    flags = flags or UserNameFlag.uint8
  if ctx.password != "":
    flags = flags or PasswordFlag.uint8
  var pkt = newPkt(Connect)
  pkt.put "MQTT", true
  pkt.put 4.uint8
  pkt.put flags
  pkt.put 60.uint16
  pkt.put ctx.clientId, true
  if ctx.username != "":
    pkt.put ctx.username, true
  if ctx.password != "":
    pkt.put ctx.password, true
  ctx.state = Connecting
  result = ctx.send(pkt)

proc sendDisconnect(ctx: MqttCtx): Future[bool] =
  let pkt = newPkt(Disconnect, 0)
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

  else:
    ctx.wrn("Error sending unknown package: " & $work.typ)

proc work(ctx: MqttCtx) {.async.} =
  if ctx.inWork:
    return
  ctx.inWork = true
  if ctx.state == Connected:
    var delWork: seq[MsgId]
    for msgId, work in ctx.workQueue:

      if work.wk == PubWork and work.state == WorkNew:
        if work.typ == Publish and work.qos == 0:
          if await ctx.sendWork(work): delWork.add msgId

        elif work.typ == PubAck and work.qos == 1:
          if await ctx.sendWork(work): delWork.add msgId

        elif work.typ == PubComp and work.qos == 2:
          if await ctx.sendWork(work): delWork.add msgId

        else:
          if await ctx.sendWork(work): work.state = WorkSent

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

proc onConnAck(ctx: MqttCtx, pkt: Pkt): Future[void] =
  ctx.state = Connected
  let (code, _) = pkt.getu8(1)
  if code == 0:
    ctx.dbg "Connection established"
  else:
    ctx.wrn "Connect failed, code " & $code
  result = ctx.work()

proc onPublish(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let qos = (pkt.flags shr 1) and 0x03
  var
    offset: int
    msgid: MsgId
    topic, message: string
  (topic, offset) = pkt.getstring(0, true)
  if qos == 1 or qos == 2:
    (msgid, offset) = pkt.getu16(offset)
  (message, offset) = pkt.getstring(offset, false)
  for top, cb in ctx.pubCallbacks:
    if top == topic: cb(topic, message)
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

proc onSubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  assert ctx.workQueue[msgId].state == WorkSent
  ctx.workQueue.del msgId

proc onUnsubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  assert ctx.workQueue[msgId].state == WorkSent
  ctx.workQueue.del msgId

proc onPingResp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  discard

proc handle(ctx: MqttCtx, pkt: Pkt) {.async.} =
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
    else: ctx.wrn "Unond pkt type " & $pkt.typ

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
    echo "Boom"

proc runPing(ctx: MqttCtx) {.async.} =
  echo "runping"
  while true:
    await sleepAsync ctx.pingTxInterval
    let ok = await ctx.sendPingReq()
    if not ok:
      break
    await ctx.work()

proc connectBroker(ctx: MqttCtx) {.async.} =
  ## Connect to the broker
  if ctx.pingTxInterval == 0:
    ctx.pingTxInterval = 60 * 1000

  ctx.dbg "connecting to " & ctx.host & ":" & $ctx.port
  try:
    ctx.s = await asyncnet.dial(ctx.host, ctx.port)
    if ctx.doSsl:
      when defined(ssl):
        ctx.ssl = newContext(protSSLv23, CVerifyNone)
        wrapConnectedSocket(ctx.ssl, ctx.s, handshakeAsClient)
      else:
        ctx.wrn "requested SSL session but ssl is not enabled"
        await ctx.close
        ctx.state = Error
    let ok = await ctx.sendConnect()
    if ok:
      asyncCheck ctx.runRx()
      asyncCheck ctx.runPing()
  except OSError as e:
    ctx.dbg "Error connecting to " & ctx.host & " " & e.msg
    ctx.state = Error

proc runConnect(ctx: MqttCtx) {.async.} =
  ## Auto-connect and reconnect to broker
  while true:
    if ctx.state == Disabled:
      break
    elif ctx.state in [Disconnected, Error]:
      await ctx.connectBroker()
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
    ctx.pingTxInterval = txInterval * 1000

proc set_host*(ctx: MqttCtx, host: string, port: int=1883, doSsl=false) =
  ## Set the MQTT host
  ctx.host = host
  ctx.port = Port(port)
  ctx.doSsl = doSsl

proc set_auth*(ctx: MqttCtx, username: string, password: string) =
  ## Set the authentication for the host.
  ctx.username = username
  ctx.password = password

proc connect*(ctx: MqttCtx) {.async.} =
  ## Connect to the broker.
  await ctx.connectBroker()

proc isConnected*(ctx: MqttCtx): bool =
  ## Returns true, if the client is connected to the broker.
  if ctx.state == Connected:
    result = true

proc start*(ctx: MqttCtx) {.async.} =
  ## Auto-connect and reconnect to the broker. The client will try to
  ## reconnect when the state is `Disconnected` or `Error`. The `Error`-state
  ## happens, when the broker is down, but the client will try to reconnect
  ## until the broker is up again.
  ctx.state = Disconnected
  asyncCheck ctx.runConnect()

proc disconnect*(ctx: MqttCtx) {.async.} =
  ## Disconnect from the broker.
  await ctx.close("User request")
  ctx.state = Disabled

proc publish*(ctx: MqttCtx, topic: string, message: string, qos=0, retain=false) {.async.} =
  ## Publish a message
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, qos: qos, message: message, retain: retain, typ: Publish)
  await ctx.work()

proc subscribe*(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback): Future[void] =
  ## Subscribe to a topic.
  ##
  ## Access the callback with:
  ## .. code-block::nim
  ##    proc callbackName(topic: string, message: string) =
  ##      echo "Topic: ", topic, ": ", message
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, qos: qos, typ: Subscribe)
  ctx.pubCallbacks[topic] = callback
  result = ctx.work()

proc unsubscribe*(ctx: MqttCtx, topic: string): Future[void] =
  ## Unsubscribe to a topic.
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, typ: Unsubscribe)
  result = ctx.work()


