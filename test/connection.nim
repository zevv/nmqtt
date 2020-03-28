
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


  #[test "connection wrong port - timeout":
    proc conn() {.async.} =
      let ctx = newMqttCtx("nmqttTestConn")
      ctx.set_host("test.mosquitto.org", 2222)
      await ctx.start()
      check(ctx.state == Error)
    waitFor conn()]#


  test "connect() to broker":
    ## FAILS. Due to `runConnect` it will reconnect forever

    proc conn() {.async.} =
      await ctxSlave.connect()
      await sleepAsync(500)
      check(ctxSlave.state == Connected)

      # Do important stuff
      await sleepAsync(500)

      # Disconnect
      await ctxSlave.disconnect()
      check(ctxSlave.state == Disabled)

    waitFor conn()


  test "start() and reconnect":
    ## FAILS. Due to `runConnect` it will reconnect forever

    proc conn() {.async.} =
      await sleepAsync(500)
      await ctxSlave.start()
      await sleepAsync(500)
      check(ctxSlave.state == Connected)

      # Do important stuff
      await sleepAsync(500)

      # Close connection
      ctxSlave.state = Disconnecting
      ctxSlave.s.close()
      echo(ctxSlave.state) # = Disconnected
      await sleepAsync(500)

      # Auto-reconnect goes on `Disconnected"
      ctxSlave.state = Disconnected
      # Auto-reconnect loop is 1000ms, wait 2000ms to ensure loop
      await sleepAsync(2000)

      # Check reconnect
      check(ctxSlave.state == Connected)

      # Disconnect
      await ctxSlave.disconnect()
      check(ctxSlave.state == Disabled)

    waitFor conn()


  test "isConnected()":
    ## FAILS. Due to `runConnect` it will reconnect forever

    proc conn() {.async.} =
      check(ctxSlave.isConnected() == false)
      await ctxSlave.connect()
      await sleepAsync(500)
      check(ctxSlave.isConnected() == true)

      await ctxSlave.disconnect()
      check(ctxSlave.state == Disabled)

    waitFor conn()