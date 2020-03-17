
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


  test "publish multiple message fast":
    let (tpc, _) = tdata("publish multiple message fast")

    proc conn() {.async.} =
      var msg: int
      for i in 1 .. 100:
        await ctxMain.publish(tpc, $msg, 0)
        msg += 1

      await sleepAsync(500) # wait for msg to be received
      check(msg == 100)
      check(ctxMain.state == Connected)

    waitFor conn()