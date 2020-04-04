
suite "test suite for will messages":

  test "send will msg with default values":
    let (tpc, msg) = tdata("send will msg with default values")

    proc conn() {.async.} =

      const willMsg = "willmsg_qos0_retain=false"
      var willMsgCheck: bool

      proc on_data_will(topic: string, message: string) =
        if topic == tpc and message == willMsg:
          willMsgCheck = true

      await ctxListen.subscribe(tpc, 2, on_data_will)
      await sleepAsync 500

      ctxSlave.set_will(tpc, willMsg)
      await ctxSlave.connect()
      await sleepAsync 500 # Wait for full connection
      ctxSlave.s.close()
      await sleepAsync 500 # Wait for willMsg to be sent
      check(willMsgCheck == true)
      ctxSlave.willFlag = true

    waitFor conn()


  test "send will msg retained = true":
    let (tpc, msg) = tdata("send will msg retained = true")

    proc conn() {.async.} =

      const willMsg = "willmsg_qos0_retain=true"
      var
        willMsgCheck: bool
        willMsgRetain: bool

      proc on_data_will(topic: string, message: string) =
        if topic == tpc and message == willMsg:
          willMsgCheck = true

      await ctxListen.subscribe(tpc, 2, on_data_will)
      await sleepAsync 500

      # Set will and send
      ctxSlave.set_will(tpc, willMsg, retain=true)
      await ctxSlave.connect()
      await sleepAsync 500 # Wait for full connection
      ctxSlave.s.close()
      await sleepAsync 500 # Wait for willMsg to be sent
      check(willMsgCheck == true)

      # Check that the message is retained.
      # New client but on same topic.
      let ctxDestroy = newMqttCtx("nmqttTestWill")
      ctxDestroy.set_host("127.0.0.1", 1883)
      await ctxDestroy.connect()

      proc on_data_will_retain(topic: string, message: string) =
        if topic == tpc and message == willMsg:
          willMsgRetain = true

      await ctxDestroy.subscribe(tpc, 2, on_data_will_retain)
      await sleepAsync 500
      check(willMsgRetain == true)
      await ctxDestroy.unsubscribe(tpc)
      await ctxDestroy.disconnect()
      ctxDestroy.willFlag = true
      await sleepAsync 500

    waitFor conn()