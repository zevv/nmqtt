
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
      await ctx.close()
      check(ctx.state == Disconnected)
      ctx.state = Disabled # It is not possible to close the connection when state is Disconnected - issues/12
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
      await ctx.close()
      check(ctx.state == Disconnected)
      ctx.state = Disabled # It is not possible to close the connection when state is Disconnected - issues/12
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

      # Disconnect
      await ctxSlave.close()

      # Make sure connection is closed
      await sleepAsync(1000)
      check(ctxSlave.state == Disconnected)

    waitFor conn()