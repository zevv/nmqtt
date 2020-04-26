
suite "test suite for messages":

  test "msgQueue() wait for all messages in workqueue":
    let (tpc, msg) = tdata("msgQueue() wait for all messages in workqueue")

    proc conn() {.async.} =

      # Send msg with no delay
      var msg: int
      for i in 0 .. 10:
        await ctxMain.publish(tpc, $msg, 2)
        msg += 1
        check(ctxMain.msgQueue > 0)

      await sleepAsync(1000)
      check(ctxMain.msgQueue == 0)

      await ctxListen.unsubscribe(tpc)

    waitFor conn()

