
suite "test suite for connections":

  test "connection public broker":
    let (tpc, msg) = tdata("connection public broker")

    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqttTestConn")
      ctx.set_host("test.mosquitto.org", 1883)
      await ctx.start()
      check(ctx.state == Connected)
      await ctx.publish(tpc, msg, 0)
      await sleepAsync(1500)
      await ctx.disconnect()
      check(ctx.state == Disabled)
    waitFor conn()


  test "connection public broker SSL":
    let (tpc, msg) = tdata("connection public broker SSL")

    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqttTestConn")
      ctx.set_host("test.mosquitto.org", 8883, true)
      await ctx.start()
      check(ctx.state == Connected)
      await ctx.publish(tpc, msg, 0)
      await sleepAsync(1500)
      await ctx.disconnect()
      check(ctx.state == Disabled)
    waitFor conn()


  test "connection wrong port - timeout":
    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqttTestConn")
      ctx.set_host("test.mosquitto.org", 2222)
      await ctx.start()
      check(ctx.state == Error)
    waitFor conn()


  test "connect and disconnect, forget":
    ## FAILS. Due to `runConnect` it will reconnect forever

    proc conn() {.async.} =
      await ctxSlave.start()
      check(ctxSlave.state == Connected)

      # Do important stuff
      await sleepAsync(500)

      # Close connection
      await ctxSlave.close("User request")
      check(ctxSlave.state == Disconnected)

      # Disconnect
      await ctxSlave.disconnect()
      check(ctxSlave.state == Disabled)

    waitFor conn()