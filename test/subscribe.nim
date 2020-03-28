
suite "test suite for subscribe":

  test "subscribe to topic qos=0":
    let (tpc, msg) = tdata("subscribe to topic qos=0")

    proc conn() {.async.} =
      proc on_data_sub_qos0(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 0, on_data_sub_qos0)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):") # and testDmp[1][1] == "00 01 00 ")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")

    waitFor conn()


  test "subscribe to topic qos=1":
    let (tpc, msg) = tdata("subscribe to topic qos=1")

    proc conn() {.async.} =
      proc on_data_sub_qos1(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 1, on_data_sub_qos1)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 1)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):") # and testDmp[1][1] == "00 02 01 ") # and testDmp[1][1] == "00 01 01 ")
      check(testDmp[2][0] == "tx> Publish(02):")
      check(testDmp[3][0] == "rx> PubAck(00):") # and testDmp[3][1] == "00 02 ") # and testDmp[3][1] == "00 01 ")
      check(testDmp[4][0] == "rx> Publish(02):")
      check(testDmp[5][0] == "tx> PubAck(02):") # and testDmp[5][1] == "00 01 ") # and testDmp[5][1] == "00 01 ")

    waitFor conn()


  test "subscribe to topic qos=2":
    let (tpc, msg) = tdata("subscribe to topic qos=2")

    proc conn() {.async.} =
      proc on_data_sub_qos2(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 2, on_data_sub_qos2)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 2)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):") # and testDmp[1][1] == "00 03 02 ") # and testDmp[1][1] == "00 01 02 ")
      check(testDmp[2][0] == "tx> Publish(04):")
      check(testDmp[3][0] == "rx> PubRec(00):") # and testDmp[3][1] == "00 03 ") # and testDmp[3][1] == "00 01 ")
      check(testDmp[4][0] == "tx> PubRel(02):") # and testDmp[4][1] == "00 03 ") # and testDmp[4][1] == "00 01 ")
      check(testDmp[5][0] == "rx> PubComp(00):") # and testDmp[5][1] == "00 03 ") # and testDmp[5][1] == "00 01 ")
      check(testDmp[6][0] == "rx> Publish(04):")
      check(testDmp[7][0] == "tx> PubRec(02):") # and testDmp[7][1] == "00 02 ") # and testDmp[7][1] == "00 01 ")
      check(testDmp[8][0] == "rx> PubRel(02):") # and testDmp[8][1] == "00 02 ") # and testDmp[8][1] == "00 01 ")
      check(testDmp[9][0] == "tx> PubComp(02):") # and testDmp[9][1] == "00 02 ")

    waitFor conn()


  test "subscribe to multiple topics":
    let (tpc, msg) = tdata("subscribe to multiple topics")

    proc conn() {.async.} =
      var
        topic1: bool
        topic2: bool

      proc on_data_sub_mul1(topic: string, message: string) =
        check(message == msg & "-mul1")
        if topic1 == true:
          topic1 = false
        else:
          topic1 = true

      proc on_data_sub_mul2(topic: string, message: string) =
        check(message == msg & "-mul2")
        if topic2 == true:
          topic2 = false
        else:
          topic2 = true

      await ctxListen.subscribe(tpc & "-1", 0, on_data_sub_mul1)
      await ctxListen.subscribe(tpc & "-2", 0, on_data_sub_mul2)
      await sleepAsync 500
      await ctxMain.publish(tpc & "-1", msg & "-mul1", 0)
      await ctxMain.publish(tpc & "-2", msg & "-mul2", 0)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc & "-1")
      await ctxListen.unsubscribe(tpc & "-2")
      await sleepAsync 500
      check(topic1 == true)
      check(topic2 == true)

    waitFor conn()


  test "subscribe to multiple with identical topic":
    let (tpc, msg) = tdata("subscribe to multiple with identical topic")

    proc conn() {.async.} =
      var
        sub1: int
        sub2: int
        sub3: int

      proc on_data_sub_mul1(topic: string, message: string) =
        if topic == tpc:
          sub1 += 1

      proc on_data_sub_mul2(topic: string, message: string) =
        if topic == tpc:
          sub2 += 1

      proc on_data_sub_mul3(topic: string, message: string) =
        if topic == tpc:
          sub3 += 1

      check(ctxListen.pubCallbacks.len() == 0)

      # Add 1 msg to sub1
      await ctxListen.subscribe(tpc, 0, on_data_sub_mul1)
      await ctxMain.publish(tpc, msg, 0)

      check(ctxListen.pubCallbacks.len() == 1)
      await sleepAsync 500

      await ctxListen.subscribe(tpc, 0, on_data_sub_mul2)

      # sub3 now overrides sub1 and sub2
      await ctxListen.subscribe(tpc, 0, on_data_sub_mul3)

      check(ctxListen.pubCallbacks.len() == 1)

      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0)
      await ctxMain.publish(tpc, msg, 0)
      await ctxMain.publish(tpc, msg, 0)
      await sleepAsync 500

      await ctxListen.unsubscribe(tpc)
      check(ctxListen.pubCallbacks.len() == 0)

      check(sub1 == 1)
      check(sub2 == 0)
      check(sub3 == 3)
      await sleepAsync 500

    waitFor conn()


  test "subscribe to #":
    let (_, msg) = tdata("subscribe to #")

    proc conn() {.async.} =
      var msgCount: int
      proc on_data_sub_all(topic: string, message: string) =
        msgCount += 1

      await ctxListen.subscribe("#", 0, on_data_sub_all)
      await sleepAsync 500
      await ctxMain.publish("random1", msg, 0)
      await ctxMain.publish("random2", msg, 0)
      await ctxMain.publish("random3", msg, 0)
      await sleepAsync 500
      await ctxListen.unsubscribe("#")
      await sleepAsync 500
      check(msgCount == 3)

    waitFor conn()


