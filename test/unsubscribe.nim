suite "test suite for unsubscribe":

  test "unsubscribe from topic":
    let (tpc, msg) = tdata("unsubscribe from topic")

    proc conn() {.async.} =
      proc on_data_unsub(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return

      check(ctxListen.pubCallbacks.len() == 0)

      await ctxListen.subscribe(tpc, 0, on_data_unsub)

      check(ctxListen.pubCallbacks.len() == 1)

      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc)

      check(ctxListen.pubCallbacks.len() == 0)

      await sleepAsync 500
      await ctxMain.publish(tpc, "Msg must not be received", 0)
      await sleepAsync 500

      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):") # and testDmp[1][1] == "00 01 00 ")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")
      check(testDmp[4][0] == "tx> Unsubscribe(02):")
      check(testDmp[5][0] == "rx> Unsuback(00):")
      check(testDmp[6][0] == "tx> Publish(00):")
      check(testDmp.len() == 7)

    waitFor conn()


  test "unsubscribe from one of many topics":
    let (tpc, msg) = tdata("unsubscribe from one of many topics")

    proc conn() {.async.} =
      var
        topic2: bool

      proc on_data_unsub1(topic: string, message: string) =
        check(message == msg)

      proc on_data_unsub2(topic: string, message: string) =
        check(message == msg)
        topic2 = true

      check(ctxListen.pubCallbacks.len() == 0)

      await ctxListen.subscribe(tpc & "-1", 0, on_data_unsub1)
      await ctxListen.subscribe(tpc & "-2", 0, on_data_unsub2)

      check(ctxListen.pubCallbacks.len() == 2)

      await sleepAsync 500
      await ctxListen.unsubscribe(tpc & "-2")

      check(ctxListen.pubCallbacks.len() == 1)

      await sleepAsync 500
      await ctxMain.publish(tpc & "-1", msg, 0)
      await ctxMain.publish(tpc & "-2", msg, 0)
      await sleepAsync 500
      await ctxListen.unsubscribe(tpc & "-1")

      check(ctxListen.pubCallbacks.len() == 0)

      check(topic2 == false)

    waitFor conn()