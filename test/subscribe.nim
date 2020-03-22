
suite "test suite for subscribe":

  test "subscribe to topic qos=0":
    let (tpc, msg) = tdata("subscribe to topic qos=1")

    proc conn() {.async.} =
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 0, on_data)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0)
      await sleepAsync 500

      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):" and testDmp[1][1] == "00 01 00 ")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")

    waitFor conn()


  test "subscribe to topic qos=1":
    let (tpc, msg) = tdata("subscribe to topic qos=1")

    proc conn() {.async.} =
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 1, on_data)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 1)
      await sleepAsync 500

      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):" and testDmp[1][1] == "00 01 01 ")
      check(testDmp[2][0] == "tx> Publish(02):")
      check(testDmp[3][0] == "rx> PubAck(00):" and testDmp[3][1] == "00 01 ")
      check(testDmp[4][0] == "rx> Publish(02):")
      check(testDmp[5][0] == "tx> PubAck(02):" and testDmp[5][1] == "00 01 ")

    waitFor conn()

  
  test "subscribe to topic qos=2":
    let (tpc, msg) = tdata("subscribe to topic qos=2")

    proc conn() {.async.} =
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 2, on_data)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 2)
      await sleepAsync 500

      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):" and testDmp[1][1] == "00 01 02 ")
      check(testDmp[2][0] == "tx> Publish(04):")
      check(testDmp[3][0] == "rx> PubRec(00):" and testDmp[3][1] == "00 01 ")
      check(testDmp[4][0] == "tx> PubRel(02):" and testDmp[4][1] == "00 01 ")
      check(testDmp[5][0] == "rx> PubComp(00):" and testDmp[5][1] == "00 01 ")
      check(testDmp[6][0] == "rx> Publish(04):")
      check(testDmp[7][0] == "tx> PubRel(02):" and testDmp[7][1] == "00 01 ")
      check(testDmp[8][0] == "rx> PubComp(00):" and testDmp[8][1] == "00 01 ")

    waitFor conn()


