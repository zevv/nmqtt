
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

    waitFor conn()


