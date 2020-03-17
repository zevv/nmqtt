
suite "test suite for publish":

  test "publish retain msg":
    ## Awaiting PR #16

    let (tpc, msg) = tdata("publish retain msg")
    waitFor ctxMain.publish(tpc, msg, qos=2, retain=true, true)

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int

      # Start listening slave
      await ctxSlave.start()
      proc on_data(topic: string, message: string) =
        echo topic
        if topic == tpc:
          check(message == msg)
          msgFound = true
          return

      await ctxMain.subscribe(tpc, 2, on_data)

      # Wait for retained msg is found
      while not msgFound:
        if timeout == 5:
          # In an ideal world this should take 0sec, but to include
          # bad connections and latency we wait 5sec.
          check(msgFound == true)
          break
        await sleepAsync(1000)
        timeout += 1

      await ctxSlave.close()
      ctxSlave.state = Disabled

    waitFor conn()


  #[
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
]#