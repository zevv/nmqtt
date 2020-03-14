
#{.experimental: "codeReordering".}

import strutils
import asyncnet
import net
import os
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
    pubCallbacks: seq[PubCallback]

  State = enum
    Disabled, Disconnected, Connecting, Connected, Disconnecting

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
  if true:
    stderr.write "\e[1;30m" & s & "\e[0m\n"

proc dbg(ctx: MqttCtx, s: string) =
  stderr.write "\e[37m" & s & "\e[0m\n"

proc wrn(ctx: MqttCtx, s: string) =
  stderr.write "\e[1;31m" & s & "\e[0m\n"

proc nextMsgId(ctx: MqttCtx): MsgId =
  inc ctx.msgIdSeq
  return ctx.msgIdSeq

proc sendDisconnect(ctx: MqttCtx): Future[bool] {.async.}

proc close(ctx: MqttCtx, reason: string="User request") {.async.} =
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

  let len = pkt.data.len

  if len <= 127:
    hdr.add len.uint8
  elif len <= 16383:
    hdr.add ((len /% 128) or 0x80).uint8
    hdr.add (len mod 128).uint8

  ctx.dmp "tx> " & $pkt
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


proc sendConnect(ctx: MqttCtx): Future[bool] {.async.} =
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
  return await ctx.send(pkt)

proc sendDisconnect(ctx: MqttCtx): Future[bool] {.async.} =
  let pkt = newPkt(Disconnect, 0)
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

proc sendPubAck(ctx: MqttCtx, msgId: MsgId): Future[bool] {.async.} =
  var pkt = newPkt(PubAck, 0b0010)
  pkt.put msgId.uint16
  return await ctx.send(pkt)

proc sendPubRel(ctx: MqttCtx, msgId: MsgId): Future[bool] {.async.} =
  var pkt = newPkt(PubRel, 0b0010)
  pkt.put msgId.uint16
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

proc onConnAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  ctx.state = Connected
  let (code, _) = pkt.getu8(1)
  if code == 0:
    ctx.dbg "Connection established"
  else:
    ctx.wrn "Connect failed, code " & $code
  await ctx.work()

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
  for cb in ctx.pubCallbacks:
    cb(topic, message)
  if qos == 1:
    let ok = await ctx.sendPubAck(msgid)
  if qos == 2:
    let ok = await ctx.sendPubRel(msgid)


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
  var pkt = newPkt(PubRel, 0b0010)
  pkt.put(msgId)
  if await ctx.send(pkt):
    ctx.workQueue.del msgId

proc onPubComp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  discard

proc onSubAck(ctx: MqttCtx, pkt: Pkt) {.async.} =
  let (msgId, _) = pkt.getu16(0)
  assert msgId in ctx.workQueue
  assert ctx.workQueue[msgId].wk == SubWork
  ctx.workQueue.del msgId

proc onPingResp(ctx: MqttCtx, pkt: Pkt) {.async.} =
  discard

proc handle(ctx: MqttCtx, pkt: Pkt) {.async.} =
  case pkt.typ
    of ConnAck: await ctx.onConnAck(pkt)
    of Publish: await ctx.onPublish(pkt)
    of PubAck: await ctx.onPubAck(pkt)
    of PubRec: await ctx.onPubRec(pkt)
    of PubComp: await ctx.onPubComp(pkt)
    of SubAck: await ctx.onSubAck(pkt)
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
  while true:
    await sleepAsync 1000
    let ok = await ctx.sendPingReq()
    if not ok:
      break
    await ctx.work()

proc runConnect(ctx: MqttCtx) {.async.} =
  while true:
    if ctx.state == Disconnected:
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
            return
        let ok = await ctx.sendConnect()
        if ok:
          asyncCheck ctx.runRx()
          asyncCheck ctx.runPing()
      except OSError as e:
        ctx.dbg "Error connecting to " & ctx.host & " " & e.msg

    await sleepAsync 1000

#
# Public API
#

proc newMqttCtx*(clientId: string): MqttCtx =
  MqttCtx(clientId: clientId)

proc set_host*(ctx: MqttCtx, host: string, port: int=1883, doSsl=false) =
  ctx.host = host
  ctx.port = Port(port)
  ctx.doSsl = doSsl

proc set_auth*(ctx: MqttCtx, username: string, password: string) =
  ctx.username = username
  ctx.password = password

proc start*(ctx: MqttCtx) {.async.} =
  ctx.state = Disconnected
  asyncCheck ctx.runConnect()

proc publish*(ctx: MqttCtx, topic: string, message: string, qos=0) {.async.} =
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: PubWork, msgId: msgId, topic: topic, message: message, qos: qos)
  await ctx.work()

proc subscribe*(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback) {.async.} =
  let msgId = ctx.nextMsgId()
  ctx.workQueue[msgId] = Work(wk: SubWork, msgId: msgId, topic: topic, qos: qos)
  ctx.pubCallbacks.add callback
  await ctx.work()

when isMainModule:
  proc flop() {.async.} =
    let ctx = newMqttCtx("hallo")

    #ctx.set_host("test.mosquitto.org", 1883)

    ctx.set_host("test.mosquitto.org", 8883, true)

    await ctx.start()
    proc on_data(topic: string, message: string) =
      echo "got ", topic, ": ", message

    await ctx.subscribe("#", 2, on_data)
    #await ctx.publish("test1", "hallo", 2)
    #await sleepAsync 1000
    #await ctx.close()

  asyncCheck flop()
  runForever()


# vi: ft=nim et ts=2 sw=2

