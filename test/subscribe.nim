
suite "test suite for subscribe":

  test "subscribe to topic":
    let (tpc, msg) = tdata("subscribe to topic")

    proc conn() {.async.} =
      proc on_data(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return

      await ctxMain.subscribe(tpc, 2, on_data)
      await ctxMain.publish(tpc, msg, 1)

    waitFor conn()


