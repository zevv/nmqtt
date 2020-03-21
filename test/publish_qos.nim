# Copyright 2020 - Thomas T. Jarløv


suite "test suite for publish with qos":

  test "publish multiple message fast qos=0":
    let (tpc, _) = tdata("publish multiple message fast qos=0")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      # Checking for final msg
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          # and message == "final":
          check(message == $msgRec)
          msgRec += 1
          if msgRec == 99:
            msgFound = true
            return

      # Start listening
      await ctxSlave.start()
      await ctxSlave.subscribe(tpc, 2, on_data)

      # Send msg with no delay
      var msg: int
      for i in 1 .. 100:
        await ctxMain.publish(tpc, $msg, 0)
        msg += 1

      check(msg == 100)
      check(ctxMain.state == Connected)

      # Wait for final msg is found
      while not msgFound:
        if timeout == 5:
          check(msgFound == true)
          break
        await sleepAsync(1000)
        timeout += 1

      await ctxSlave.close("Close ctxSlave")
      ctxSlave.state = Disabled

    waitFor conn()


  test "publish multiple message fast qos=1":
    let (tpc, _) = tdata("publish multiple message fast qos=1")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      # Checking for final msg
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          # and message == "final":
          check(message == $msgRec)
          msgRec += 1
          if msgRec == 99:
            msgFound = true
            return

      # Start listening
      await ctxSlave.start()
      await ctxSlave.subscribe(tpc, 2, on_data)

      # Send msg with no delay
      var msg: int
      for i in 1 .. 100:
        await ctxMain.publish(tpc, $msg, 1)
        msg += 1

      check(msg == 100)
      check(ctxMain.state == Connected)

      # Wait for final msg is found
      while not msgFound:
        if timeout == 5:
          check(msgFound == true)
          break
        await sleepAsync(1000)
        timeout += 1

      await ctxSlave.close("Close ctxSlave")
      ctxSlave.state = Disabled

    waitFor conn()


  test "publish multiple message fast qos=2":
    let (tpc, _) = tdata("publish multiple message fast qos=2")

    proc conn() {.async.} =
      var
        msgFound: bool
        timeout: int
        msgRec: int

      # Checking for final msg
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          # and message == "final":
          check(message == $msgRec)
          msgRec += 1
          if msgRec == 99:
            msgFound = true
            return

      # Start listening
      await ctxSlave.start()
      await ctxSlave.subscribe(tpc, 2, on_data)

      # Send msg with no delay
      var msg: int
      for i in 1 .. 100:
        await ctxMain.publish(tpc, $msg, 2)
        msg += 1

      check(msg == 100)
      check(ctxMain.state == Connected)

      # Wait for final msg is found
      while not msgFound:
        if timeout == 5:
          check(msgFound == true)
          break
        await sleepAsync(1000)
        timeout += 1

      await ctxSlave.close("Close ctxSlave")
      ctxSlave.state = Disabled

    waitFor conn()