const msgCount = 500

suite "test suite for publish with qos":

  test "publish multiple message fast qos=0":
    let (tpc, _) = tdata("publish multiple message fast qos=0")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      await sleepAsync 1000

      proc on_data_qos0(topic: string, message: string) =
        if topic == tpc:
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data_qos0)

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
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()


  test "publish multiple message fast qos=1":
    let (tpc, _) = tdata("publish multiple message fast qos=1")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      await sleepAsync(2000)

      proc on_data_qos1(topic: string, message: string) =
        if topic == tpc:
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data_qos1)

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
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()


  test "publish multiple message fast qos=2":
    let (tpc, _) = tdata("publish multiple message fast qos=2")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      await sleepAsync(2000)

      proc on_data_qos2(topic: string, message: string) =
        if topic == tpc:
          msgRec += 1
          if msgRec == msgCount:
            msgFound = true
            return
      await ctxListen.subscribe(tpc, 0, on_data_qos2)

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
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()