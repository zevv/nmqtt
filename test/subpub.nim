# Copyright 2020 - Thomas T. Jarløv

import asyncdispatch, unittest, random

include ../src/nmqtt

randomize()
let ctx = newMqttCtx("nmqtttest")
ctx.set_ping_interval(60) # To be removed
#ctx.set_host("test.mosquitto.org", 1883)
ctx.set_host("127.0.0.1", 1883)

suite "unit tests":

  test "subscribe to topic":
    echo "\n\n"
    proc conn() {.async.} =
      let msg = $rand(9999)
      await ctx.start()
      proc on_data(topic: string, message: string) =
        if topic == "nmqtttest":
          check(message == msg)
          waitFor ctx.close()
          check(ctx.state == Disconnected)
          ctx.state = Disabled

      await ctx.subscribe("nmqtttest", 2, on_data)
      await ctx.publish("nmqtttest", msg, 1)

    waitFor conn()


  test "publish qos 2":
    echo "\n\n"
    proc conn() {.async.} =
      let msg = $rand(9999)
      await ctx.start()
      await ctx.publish("nmqtttest", msg, 2)
      await sleepAsync(1500)
      await ctx.close()

      await ctx.start()
      proc on_data(topic: string, message: string) =
        if topic == "nmqtttest":
          check(message == msg)
          #await ctx.close()

    waitFor conn()


  test "publish multiple message fast":
    echo "\n\n"
    proc conn() {.async.} =
      await ctx.start()
      var count: int
      while true:
        #await sleepAsync(50) - needed until PR #13
        asyncCheck ctx.publish("nmqtttest", $rand(9999), 0)
        count += 1
        if count == 10:
          check(ctx.state == Connected)
          break
      await sleepAsync(2000)
      await ctx.close()

    waitFor conn()

    ## Fails, awaiting PR #13
