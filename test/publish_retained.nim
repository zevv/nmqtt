
suite "test suite for publish retained":

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
        if topic == tpc:
          check(message == msg)
          msgFound = true
          return

      await ctxSlave.subscribe(tpc, 2, on_data)

      # Wait for retained msg is found
      while not msgFound:
        if timeout == 5:
          # In an ideal world this should take 0sec, but to include
          # bad connections and latency we wait 5sec.
          check(msgFound == true)
          break
        await sleepAsync(1000)
        timeout += 1

      await ctxSlave.disconnect()
      ctxSlave.state = Disabled

    waitFor conn()