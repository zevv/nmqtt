
Native Nim MQTT client library. Alpha quality.

Usage:


```

import nmqtt

let ctx = newMqttCtx("hallo")

ctx.set_host("test.mosquitto.org", 1883)

await ctx.start()
proc on_data(topic: string, message: string) =
  echo "got ", topic, ": ", message

await s.publish("test1", "hallo", 2)
await ctx.subscribe("#", 0, on_data)

asyncCheck flop()
runForever()

```
