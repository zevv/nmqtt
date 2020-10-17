
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
      # We need all these sleepAsync cause it's too fast in -d:release
      await sleepAsync 500
      proc on_data_sub_qos2(topic: string, message: string) =
        if topic == tpc:
          check(message == msg)
          return
      await ctxListen.subscribe(tpc, 2, on_data_sub_qos2)
      await sleepAsync 1000
      await ctxMain.publish(tpc, msg, 2)
      await sleepAsync 1000
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 1000
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
      # TODO: This failes without the sleepAsync due to `len(t) == L` the length of the table changed while iterating over it
      await sleepAsync 500
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

  test "subscribe to test/#":
    let (_, msg) = tdata("subscribe to test/#")

    proc conn() {.async.} =
      var msgCount: int
      proc on_data_sub_wild(topic: string, message: string) =
        msgCount += 1

      await ctxListen.subscribe("test/#", 0, on_data_sub_wild)
      await sleepAsync 500
      await ctxMain.publish("test/random1", msg, 0)
      await ctxMain.publish("second/random2", msg, 0)
      await ctxMain.publish("test/random3", msg, 0)
      await sleepAsync 500
      await ctxListen.unsubscribe("test/#")
      await sleepAsync 500
      check(msgCount == 2)

    waitFor conn()

  test "stay subscribed after disconnect with reconnect":
    let (tpc, msg) = tdata("stay subscribed after disconnect with reconnect")

    proc conn() {.async.} =
      await ctxSlave.start()
      await sleepAsync(1000)
      testDmp = @[]

      var msgCount: int
      proc on_data_sub_keep(topic: string, message: string) =
        msgCount += 1

      await ctxSlave.subscribe(tpc, 0, on_data_sub_keep)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0) # msg 1
      await sleepAsync 500

      # Disconnect
      ctxSlave.state = Disconnecting
      ctxSlave.s.close()
      await sleepAsync(500)
      ctxSlave.state = Disconnected
      await sleepAsync(2000) # Auto-reconnect loop is 1000ms, wait 2000ms to ensure loop
      # We should automatic reconnect here

      await ctxMain.publish(tpc, msg, 0) # msg 2
      await ctxMain.publish(tpc, msg, 0) # msg 3
      await sleepAsync 500
      await ctxSlave.unsubscribe(tpc)
      await sleepAsync 500

      check(msgCount == 3) # A total of 3 msgs on this topic
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")
      # Disconnected
      check(testDmp[4][0] == "tx> Connect(00):")
      check(testDmp[5][0] == "rx> ConnAck(00):")
      # Re-subscribe
      check(testDmp[6][0] == "tx> Subscribe(02):")
      check(testDmp[7][0] == "rx> SubAck(00):")
      check(testDmp[8][0] == "tx> Publish(00):")
      check(testDmp[9][0] == "tx> Publish(00):")
      check(testDmp[10][0] == "rx> Publish(00):")
      check(testDmp[11][0] == "rx> Publish(00):")
      # Unsub
      check(testDmp[12][0] == "tx> Unsubscribe(02):")
      check(testDmp[13][0] == "rx> Unsuback(00):")

      await ctxSlave.disconnect()
      await sleepAsync(1000)

    waitFor conn()


  test "stay subscribed after disconnect with reconnect with same qos=2":
    let (tpc, msg) = tdata("stay subscribed after disconnect with reconnect with same qos=2")

    proc conn() {.async.} =
      await ctxSlave.start()
      await sleepAsync(1000)
      testDmp = @[]

      var msgCount: int
      proc on_data_sub_keep(topic: string, message: string) =
        msgCount += 1

      await ctxSlave.subscribe(tpc, 2, on_data_sub_keep)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0) # msg 1
      await sleepAsync 500

      # Disconnect
      ctxSlave.state = Disconnecting
      ctxSlave.s.close()
      await sleepAsync(500)
      ctxSlave.state = Disconnected
      await sleepAsync(2000) # Auto-reconnect loop is 1000ms, wait 2000ms to ensure loop
      # We should automatic reconnect here

      await ctxMain.publish(tpc, msg, 2) # msg 2
      #await ctxMain.publish(tpc, msg, 0) # msg 3
      await sleepAsync 500
      await ctxSlave.unsubscribe(tpc)
      await sleepAsync 500

      check(msgCount == 2) # A total of 3 msgs on this topic

      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")

      # Disconnected
      check(testDmp[4][0] == "tx> Connect(00):")
      check(testDmp[5][0] == "rx> ConnAck(00):")

      # Re-subscribe
      check(testDmp[6][0] == "tx> Subscribe(02):")
      check(testDmp[7][0] == "rx> SubAck(00):")

      # Publish - qos=2
      check(testDmp[8][0] == "tx> Publish(04):")
      check(testDmp[9][0] == "rx> PubRec(00):")
      check(testDmp[10][0] == "tx> PubRel(02):")
      check(testDmp[11][0] == "rx> PubComp(00):")

      # Subscribe - receive - qos=2
      check(testDmp[12][0] == "rx> Publish(04):")
      check(testDmp[13][0] == "tx> PubRec(02):")
      check(testDmp[14][0] == "rx> PubRel(02):")
      check(testDmp[15][0] == "tx> PubComp(02):")

      # Unsub
      check(testDmp[16][0] == "tx> Unsubscribe(02):")
      check(testDmp[17][0] == "rx> Unsuback(00):")

      await ctxSlave.disconnect()
      await sleepAsync(1000)

    waitFor conn()


  test "stay subscribed after multipe (2) disconnect with reconnect":
    let (tpc, msg) = tdata("stay subscribed after multipe (2) disconnect with reconnect")

    proc conn() {.async.} =
      await ctxSlave.start()
      await sleepAsync(1000)
      testDmp = @[]

      var msgCount: int
      proc on_data_sub_keep_multiple(topic: string, message: string) =
        msgCount += 1

      await ctxSlave.subscribe(tpc, 0, on_data_sub_keep_multiple)
      await sleepAsync 500
      await ctxMain.publish(tpc, msg, 0) # msg 1
      await sleepAsync 500

      # Disconnect 1/2
      ctxSlave.state = Disconnecting
      ctxSlave.s.close()
      await sleepAsync(500)
      ctxSlave.state = Disconnected
      await sleepAsync(2000) # Auto-reconnect loop is 1000ms, wait 2000ms to ensure loop
      # We should automatic reconnect here

      # Disconnect 2/2
      ctxSlave.state = Disconnecting
      ctxSlave.s.close()
      await sleepAsync(500)
      ctxSlave.state = Disconnected
      await sleepAsync(2000) # Auto-reconnect loop is 1000ms, wait 2000ms to ensure loop
      # We should automatic reconnect here

      await ctxMain.publish(tpc, msg, 0) # msg 2
      await ctxMain.publish(tpc, msg, 0) # msg 3
      await sleepAsync 500
      await ctxSlave.unsubscribe(tpc)
      await sleepAsync 500

      check(msgCount == 3) # A total of 3 msgs on this topic
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")

      # Disconnected 1/2
      check(testDmp[4][0] == "tx> Connect(00):")
      check(testDmp[5][0] == "rx> ConnAck(00):")
      # Re-subscribe
      check(testDmp[6][0] == "tx> Subscribe(02):")
      check(testDmp[7][0] == "rx> SubAck(00):")

      # Disconnected 1/2
      check(testDmp[8][0] == "tx> Connect(00):")
      check(testDmp[9][0] == "rx> ConnAck(00):")
      # Re-subscribe
      check(testDmp[10][0] == "tx> Subscribe(02):")
      check(testDmp[11][0] == "rx> SubAck(00):")

      check(testDmp[12][0] == "tx> Publish(00):")
      check(testDmp[13][0] == "tx> Publish(00):")
      check(testDmp[14][0] == "rx> Publish(00):")
      check(testDmp[15][0] == "rx> Publish(00):")
      # Unsub
      check(testDmp[16][0] == "tx> Unsubscribe(02):")
      check(testDmp[17][0] == "rx> Unsuback(00):")

      await ctxSlave.disconnect()
      await sleepAsync(1000)

    waitFor conn()


  test "stay subscribed after long disconnect with reconnect":
    ## This test currently needs manual actions - you need to close/disconnect
    ## your broker during the test and open/reconnect.

    echo "\n\nTHIS TEST NEEDS MANUAL ACTIONS - STAY READY\n\n"

    let (tpc, msg) = tdata("stay subscribed after long disconnect with reconnect")

    proc conn() {.async.} =
      # Disconnect main clients to avoid interference with result
      await sleepAsync(1000)
      waitFor ctxMain.disconnect()
      waitFor ctxListen.disconnect()
      await sleepAsync(1000)

      await ctxSlave.start()
      ctxSlave.set_ping_interval(90) # Increas ping to avoid interference with package order
      await sleepAsync(1000)
      testDmp = @[]

      var msgCount: int
      proc on_data_sub_keep_long(topic: string, message: string) =
        msgCount += 1

      await ctxSlave.subscribe(tpc, 0, on_data_sub_keep_long)
      await sleepAsync 500
      await ctxSlave.publish(tpc, msg, 0) # msg 1
      await sleepAsync 500

      # Disconnect
      echo "\n\nDISCONNECT THE BROKER NOW\n\n"
      await sleepAsync(2000)

      # Publish messages while the broker is down
      await ctxSlave.publish(tpc, msg, 0) # msg 2
      await ctxSlave.publish(tpc, msg, 0) # msg 3
      await ctxSlave.publish(tpc, msg, 0) # msg 4
      await ctxSlave.publish(tpc, msg, 0) # msg 5
      await sleepAsync(5000)

      # Reconnect the broker
      echo "\n\nCONNECT THE BROKER NOW\n\n"
      await sleepAsync(4000)

      # Send messages when the broker is up again
      await ctxSlave.publish(tpc, msg, 0) # msg 2
      await ctxSlave.publish(tpc, msg, 0) # msg 3
      await sleepAsync 1500
      await ctxSlave.unsubscribe(tpc)
      await sleepAsync 500

      check(msgCount == 7)

      # Connect and send 1 messages
      check(testDmp[0][0] == "tx> Subscribe(02):")
      check(testDmp[1][0] == "rx> SubAck(00):")
      check(testDmp[2][0] == "tx> Publish(00):")
      check(testDmp[3][0] == "rx> Publish(00):")

      # Manual disconnect
      check(testDmp[4][0] == "tx> Disconnect(00):")

      # Connect
      check(testDmp[5][0] == "tx> Connect(00):")
      check(testDmp[6][0] == "rx> ConnAck(00):")

      # Re-subscribe
      check(testDmp[7][0] == "tx> Subscribe(02):")

      # Publish all messages in queue
      check(testDmp[8][0] == "tx> Publish(00):")
      check(testDmp[9][0] == "tx> Publish(00):")
      check(testDmp[10][0] == "tx> Publish(00):")
      check(testDmp[11][0] == "tx> Publish(00):")

      # Receive subscribe ack
      check(testDmp[12][0] == "rx> SubAck(00):")

      # Receive all messages
      check(testDmp[13][0] == "rx> Publish(00):")
      check(testDmp[14][0] == "rx> Publish(00):")
      check(testDmp[15][0] == "rx> Publish(00):")
      check(testDmp[16][0] == "rx> Publish(00):")

      # Publish the 2 last messages
      check(testDmp[17][0] == "tx> Publish(00):")
      check(testDmp[18][0] == "tx> Publish(00):")

      # Receive the 2 last messages
      check(testDmp[19][0] == "rx> Publish(00):")
      check(testDmp[20][0] == "rx> Publish(00):")

      # Unsub
      check(testDmp[21][0] == "tx> Unsubscribe(02):")
      check(testDmp[22][0] == "rx> Unsuback(00):")

      # Reconnect main clients
      await ctxSlave.disconnect()
      await ctxMain.start()
      await ctxListen.start()
      await sleepAsync(1000)

    waitFor conn()
