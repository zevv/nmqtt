
suite "test suite for publish":

  test "publish multi line":
    let (tpc, _) = tdata("publish multi line")

    const text = """1) If wishes were horses, beggars would ride.
    2) It’s easy to be wise after the event.
        3) Watch the doughnut, and not the hole.
            4) On a wing and a prayer"""

    proc conn() {.async.} =
      await sleepAsync 1000

      var
        msgFound: bool
        timeout: int
        msg: string

      proc on_data_pub1(topic: string, message: string) =
        if topic == tpc:
          msg = message

      await ctxListen.subscribe(tpc, 0, on_data_pub1)

      await sleepAsync 500
      await ctxMain.publish(tpc, text, 0)

      # Wait for final msg is found
      while msg == "":
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(text == msg)
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()


  test "publish json":
    let (tpc, _) = tdata("publish json")

    const text = """
{
  "Novo": {
      "priceLatest": 359.35,
      "percentToday": -1.55,
      "plusminusToday": -5.65,
      "priceBuy": 359.35,
      "priceSell": 359.35,
      "priceHighest": 381.5,
      "priceLowest": 355.75,
      "tradeTotal": 6914045,
      "orderdepthBuy": 0,
      "orderdepthSell": 0,
      "epochtime": 1584771256,
      "success": true
  }
},
{
  "Alibaba": {
      "priceLatest": 180.35,
      "percentToday": -0.55,
      "plusminusToday": -8.65,
      "priceBuy": 181.25,
      "priceSell": 180.35,
      "priceHighest": 183.5,
      "priceLowest": 179.75,
      "tradeTotal": 13264045,
      "orderdepthBuy": 0,
      "orderdepthSell": 0,
      "epochtime": 1584771256,
      "success": true
  }
}"""
    proc conn() {.async.} =
      await sleepAsync 1000

      var
        msgFound: bool
        timeout: int
        msg: string

      proc on_data_pub2(topic: string, message: string) =
        if topic == tpc:
          msg = message

      await ctxListen.subscribe(tpc, 0, on_data_pub2)

      await sleepAsync 500
      await ctxMain.publish(tpc, text, 0)

      # Wait for final msg is found
      while msg == "":
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(text == msg)
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()



  test "publish long (757 chars)":
    let (tpc, _) = tdata("publish long (757 chars)")

    const text = "Nim code specifies a computation that acts on a memory consisting of components called locations. A variable is basically a name for a location. Each variable and location is of a certain type. The variable's type is called static type, the location's type is called dynamic type. If the static type is not the same as the dynamic type, it is a super-type or subtype of the dynamic type. An identifier is a symbol declared as a name for a variable, type, procedure, etc. The region of the program over which a declaration applies is called the scope of the declaration. Scopes can be nested. The meaning of an identifier is determined by the smallest enclosing scope in which the identifier is declared unless overloading resolution rules suggest otherwise."

    proc conn() {.async.} =
      await sleepAsync 1000

      var
        msgFound: bool
        timeout: int
        msg: string

      proc on_data_pub3(topic: string, message: string) =
        if topic == tpc:
          msg = message

      await ctxListen.subscribe(tpc, 0, on_data_pub3)

      await sleepAsync 500
      await ctxMain.publish(tpc, text, 0)

      # Wait for final msg is found
      while msg == "":
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(text == msg)
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()


  test "publish special chars":
    let (tpc, _) = tdata("publish special chars")

    const text = "*~\"%?+#!öôéè|§½';£@$ 诶艾弗艾儿豆贝尔维 НимИсТчеБест æøå αγλρξψ mənʊʃjõəd̪ʱɪkaːɾõ 😆😎😍😘"

    proc conn() {.async.} =
      await sleepAsync 1000

      var
        msgFound: bool
        timeout: int
        msg: string

      proc on_data_pub3(topic: string, message: string) =
        if topic == tpc:
          msg = message
          echo msg

      await ctxListen.subscribe(tpc, 0, on_data_pub3)

      await sleepAsync 500
      await ctxMain.publish(tpc, text, 0)

      # Wait for final msg is found
      while msg == "":
        if timeout == 5:
          break
        await sleepAsync(1000)
        timeout += 1

      check(text == msg)
      await ctxListen.unsubscribe(tpc)
      await sleepAsync 500
    waitFor conn()