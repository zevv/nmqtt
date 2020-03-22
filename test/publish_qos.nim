const msgCount = 500

suite "test suite for publish with qos":

  test "publish multiple message fast qos=0":
    let (tpc, _) = tdata("publish multiple message fast qos=0")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      proc on_data(topic: string, message: string) =
        if topic == tpc:
          # and message == "final":
          check(message == $msgRec)
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data)

      # Send msg with no delay
      var msg: int
      for i in 0 .. msgCount-1:
        await ctxMain.publish(tpc, $msg, 0)
        msg += 1

      check(msg == msgCount)
      check(ctxMain.state == Connected)

      # Wait for final msg is found
      while not msgFound:
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(msgRec == msgCount)
      check(ctxMain.workQueue.len == 0) # A ping could cause a failure

    waitFor conn()


  test "publish multiple message fast qos=1":
    let (tpc, _) = tdata("publish multiple message fast qos=1")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      proc on_data(topic: string, message: string) =
        if topic == tpc:
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data)

      # Send msg with no delay
      var msg: int
      for i in 0 .. msgCount-1:
        await ctxMain.publish(tpc, $msg, 1)
        msg += 1

      check(msg == msgCount)
      check(ctxMain.state == Connected)

      # Wait for final msg is found
      while not msgFound:
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(msgRec == msgCount)
      check(ctxMain.workQueue.len == 0) # A ping could cause a failure

    waitFor conn()


  test "publish multiple message fast qos=2":
    ## FAILS messages cant keep up with the 4 way check (qos=2).
    ## Furthermore this test currently has a 100 ms delay between
    ## sending messages, otherwise it fails instantly.

    let (tpc, _) = tdata("publish multiple message fast qos=2")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      proc on_data(topic: string, message: string) =
        if topic == tpc:
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data)
      

      # Send msg with no delay
      var msg: int
      for i in 0 .. msgCount-1:
        await ctxMain.publish(tpc, $msg, 2)
        msg += 1

      check(msg == msgCount)
      check(ctxMain.state == Connected)

      while ctxMain.workQueue.len > 0:
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(msgRec == msgCount)
      check(ctxMain.workQueue.len == 0) # A ping could cause a failure

    waitFor conn()