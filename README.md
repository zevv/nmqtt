
Native Nim MQTT client library, work in progress

Usage:


```

import nmqtt, asyncdispatch

let ctx = newMqttCtx("hallo")

ctx.set_host("test.mosquitto.org", 1883)
#ctx.set_auth("username", "password")

await ctx.start()
proc on_data(topic: string, message: string) =
  echo "got ", topic, ": ", message

await ctx.publish("test1", "hallo", 2)
await ctx.subscribe("#", 0, on_data)

asyncCheck flop()
runForever()

```
