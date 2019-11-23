
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
    state: State
    clientId: string
    s: AsyncSocket
    ssl: SslContext
    msgIdSeq: MsgId
    workQueue: Table[MsgID, Work]
    pubCallbacks: seq[PubCallback]

  State = enum
    Disabled, Disconnected, Connecting, Connected
  
  MsgId = uint16

  Qos = range[0..2]

  PktType = enum
    Notype      =  0 # uninitialized
    Connect     =  1 # c->s Client request to connect to Server
    ConnAck     =  2 # s->c Connect acknowledgment 
    Publish     =  3 # c->s or s->c Publish message 
    PubAck      =  4 # c->s or s->c Publish acknowledgment 
    PubRec      =  5 # c->s or s->c Publish received (assured delivery part 1) 
    PubRel      =  6 # c->s or s->c Publish release (assured delivery part 2) 
    PubComp     =  7 # c->s or s->c Publish complete (assured delivery part 3) 
    Subscribe   =  8 # c->s Client subscribe request 
    SubAck      =  9 # s->c Subscribe acknowledgment 
    Unsubscribe = 10 # c->s Unsubscribe request 
    Unsuback    = 11 # s->c Unsubscribe acknowledgment 
    PingReq     = 12 # c->s PING request 
    PingResp    = 13 # s->c PING response 
    Disconnect  = 14 # c->s Client is disconnecting 

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
    WorkNew, WorkSent, WorkAcked

  PubCallback = proc(topic: string, message: string)

  Work = ref object
    state: WorkState
    msgId: MsgId
    topic: string
    qos: Qos
    case wk: WorkKind
    of PubWork:
      retain: bool
      message: string
    of SubWork:
      discard 

#
# Pkts
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

proc debug(ctx: MqttCtx, s: string) =
  if false:
    echo "\e[1;30m" & s & "\e[0m"

proc nextMsgId(ctx: MqttCtx): MsgId =
  inc ctx.msgIdSeq
  return ctx.msgIdSeq

proc send(ctx: MqttCtx, pkt: Pkt): Future[bool] {.async.} =

  if ctx.state notin {Connecting, Connected}:
    return false

  var hdr: seq[uint8]
  hdr.add (pkt.typ.int shl 4).uint8 or pkt.flags
  
  let len = pkt.data.len

  if len <= 127:
    hdr.add len.uint8
  elif len <= 16383:
    hdr.add ((len /% 128) or 0x80).uint8
    hdr.add (len mod 128).uint8

  ctx.debug "tx> " & $pkt
  await ctx.s.send(hdr[0].unsafeAddr, hdr.len)

  if len > 0:
    await ctx.s.send(pkt.data[0].unsafeAddr, len)

  return true

proc recv(ctx: MqttCtx): Future[Pkt] {.async.} =

  if ctx.state notin {Connecting,Connected}:
    return

  var r: int
  var b: uint8
  r = await ctx.s.recvInto(b.addr, b.sizeof)
  assert r == 1
  let typ = (b shr 4).PktType
  let flags = (b and 0x0f)
  var pkt = newPkt(typ, flags)

  var len: int
  var mul = 1
  for i in 0..3:
    var b: uint8
    r = await ctx.s.recvInto(b.addr, b.sizeof)
    assert r == 1
    inc len, (b and 127).int * mul
    mul *= 128
    if ((b.int) and 0x80) == 0:
      break

  if len > 0:
    pkt.data.setlen len
    r = await ctx.s.recvInto(pkt.data[0].addr, len)
    assert r == len
  
  ctx.debug "rx> " & $pkt
  return pkt
  
proc sendConnect(ctx: MqttCtx): Future[bool] {.async.} =
  var pkt = newPkt(Connect)
  pkt.put "MQTT", true
  pkt.put 4.uint8
  pkt.put CleanSession.uint8
  pkt.put 60.uint16
  pkt.put ctx.clientId, true
  ctx.state = Connecting
  return await ctx.send(pkt)

proc sendPublish(ctx: MqttCtx, msgId: MsgId, topic: string, message: string, qos: Qos, retain: bool): Future[bool] {.async.} =
  var flags = (qos shl 1).uint8
  if retain:
    flags = flags or 1
  var pkt = newPkt(Publish, flags)
  pkt.put topic, true
  if qos > 0:
    pkt.put msgId.uint16
  pkt.put message, false
  return await ctx.send(pkt)

proc sendSubscribe(ctx: MqttCtx, msgId: MsgId, topic: string, qos: Qos): Future[bool] {.async.} =
  var pkt = newPkt(Subscribe, 0b0010)
  pkt.put msgId.uint16
  pkt.put topic, true
  pkt.put qos.uint8
  return await ctx.send(pkt)

proc sendWork(ctx: MqttCtx, work: Work): Future[bool] {.async.} =
  return case work.wk
    of PubWork:
      await ctx.sendPublish(work.msgId, work.topic, work.message, work.qos, work.retain)
    of SubWork:
      await ctx.sendSubscribe(work.msgId, work.topic, work.qos)

proc sendPingReq(ctx: MqttCtx): Future[bool] {.async.} =
  var pkt = newPkt(Pingreq)
  return await ctx.send(pkt)

proc work(ctx: MqttCtx) {.async.} =
  if ctx.state == Connected:
    var delWork: seq[MsgId]
    for msgId, work in ctx.workQueue:
      if work.state == WorkNew:
        let ok = await ctx.sendWork(work)
        if ok:
          if work.wk == PubWork and work.qos == 0:
            delWork.add msgId
          else:
            work.state = WorkSent

    for msgId in delWork:
      ctx.workQueue.del msgId

proc handleConnAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  ctx.state = Connected
  await ctx.work()

proc handlePublish(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (topic, offset) = pkt.getstring(0, true)
  let (message, offset2) = pkt.getstring(offset, false)
  for cb in ctx.pubCallbacks:
    cb(topic, message)

proc handlePubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 1
  ctx.workQueue.del msgId

proc handlePubRec(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == PubWork
  assert ctx.workQueue[msgId].state == WorkSent
  assert ctx.workQueue[msgId].qos == 2
  var pkt = newPkt(PubRel, 0b0010)
  pkt.put(msgId)
  if await ctx.send(pkt):
    ctx.workQueue.del msgId

proc handleSubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  ctx.workQueue.del msgId

proc handlePingResp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  discard

proc handle(ctx: MqttCtx, pkt: Pkt) {.async.} =
  case pkt.typ
    of ConnAck: await ctx.handleConnAck(pkt)
    of Publish: await ctx.handlePublish(pkt)
    of PubAck: await ctx.handlePubAck(pkt)
    of PubRec: await ctx.handlePubRec(pkt)
    of SubAck: await ctx.handleSubAck(pkt)
    of PingResp: await ctx.handlePingResp(pkt)
    else: ctx.debug "Unhandled pkt type " & $pkt.typ

#
# Async work functions
#

proc runRx(ctx: MqttCtx) {.async.} =
  while true:
    var pkt = await ctx.recv()
    if pkt.typ == Notype:
      break
    await ctx.handle(pkt)

proc runPing(ctx: MqttCtx) {.async.} =
  while true:
    await sleepAsync 1000
    let ok = await ctx.sendPingReq()
    if not ok:
      break
    await ctx.work()

proc runConnect(ctx: MqttCtx) {.async.} =
  while true:
    if ctx.state == Disconnected:
      ctx.s = await asyncnet.dial(ctx.host, ctx.port)
      if ctx.doSsl:
        ctx.ssl = newContext(protSSLv23, CVerifyNone)
        wrapConnectedSocket(ctx.ssl, ctx.s, handshakeAsClient)
      let ok = await ctx.sendConnect()
      if ok:
        asyncCheck ctx.runRx()
        asyncCheck ctx.runPing()

    await sleepAsync 1000

#
# Public API
#

proc newMqttCtx(clientId: string): MqttCtx =
  result = MqttCtx(clientId: clientId)

proc connect*(ctx: MqttCtx, host: string, port: int, doSsl: bool) {.async.} =
  ctx.host = host
  ctx.port = Port(port)
  ctx.doSsl = doSsl
  ctx.state = Disconnected
  asyncCheck ctx.runConnect()

proc publish(ctx: MqttCtx, topic: string, message: string, qos=0) {.async.} =
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, message: message, qos: qos)
  await ctx.work()

proc subscribe(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback) {.async.} =
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, qos: qos)
  ctx.pubCallbacks.add callback
  await ctx.work()

when isMainModule:
  proc flop() {.async.} =
    let s = newMqttCtx("hallo")
    await s.connect("test.mosquitto.org", 1883, false)
    proc on_data(topic: string, message: string) =
      echo "got ", topic, ": ", message

    await s.subscribe("#", 0, on_data)
    #await s.publish("test1", "hallo", 2)

  asyncCheck flop()
  runForever()

# vi: ft=nim et ts=2 sw=2

