# Copyright 2020 - Thomas T. Jarløv

import asyncdispatch, unittest, random

include ../src/nmqtt

suite "unit tests":

  test "connection":
    echo "\n\n"
    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqtttest1")
      ctx.set_ping_interval(60) # To be removed
      ctx.set_host("test.mosquitto.org", 1883)
      await ctx.start()
      check(ctx.state == Connected)
      await sleepAsync(1500)
      await ctx.close()
      check(ctx.state == Disconnected)
      ctx.state = Disabled # It is not possible to close the connection when state is Disconnected - issues/12
    waitFor conn()


  test "connection SSL":
    echo "\n\n"
    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqtttest2")
      ctx.set_ping_interval(60) # To be removed
      ctx.set_host("test.mosquitto.org", 8883, true)
      await ctx.start()
      check(ctx.state == Connected)
      await sleepAsync(1500)
      await ctx.close()
      check(ctx.state == Disconnected)
      ctx.state = Disabled # It is not possible to close the connection when state is Disconnected - issues/12
    waitFor conn()

  test "connection wrong port - timeout":
    echo "\n\n"
    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqtttest1")
      ctx.set_ping_interval(60) # To be removed
      ctx.set_host("test.mosquitto.org", 2222)
      await ctx.start()
      check(ctx.state == Error)
    waitFor conn()