
suite "test suite for ping":

  test "set ping interval":
    let (tpc, msg) = tdata("set ping interval")

    proc conn() {.async.} =

      ctxSlave.set_ping_interval(1)
      await ctxSlave.connect()
      await sleepAsync(6000)

      var
        pingCount: int
        pingResp: int
      for ping in testDmp:
        if ping[0] == "tx> PingReq(00):": pingCount += 1
        if ping[0] == "rx> PingResp(00):": pingResp += 1

      checkpoint("Ping with 1 second interval during 6 seconds")
      check(pingCount > 3)
      check(pingResp > 3)

      await ctxSlave.disconnect()
      await sleepAsync(500)

      testDmp = @[]
      ctxSlave.set_ping_interval(60)
      await ctxSlave.connect()
      await sleepAsync(6000)

      pingCount = 0
      pingResp = 0
      for ping in testDmp:
        if ping[0] == "tx> PingReq(00):": pingCount += 1
        if ping[0] == "rx> PingResp(00):": pingResp += 1

      checkpoint("Ping with 60 second interval during 6 seconds")
      check(pingCount == 0)
      check(pingResp == 0)

      await ctxSlave.disconnect()
      await sleepAsync(500)

    waitFor conn()