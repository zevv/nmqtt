## Native Nim MQTT client library

This library includes all the needed `procs` for publishing MQTT messages to
a MQTT-broker and for subscribing to a topic on a MQTT-broker.

The library supports QOS 1, 2 and 3 for both publishing and subscribing.

## Examples

```nim
import nmqtt, asyncdispatch

let ctx = newMqttCtx("nmqttClient")
ctx.set_host("test.mosquitto.org", 1883)
#ctx.set_auth("username", "password")
#ctx.set_ping_interval(30)

proc mqttSub() {.async.} =
  await ctx.start()
  proc on_data(topic: string, message: string) =
    echo "got ", topic, ": ", message

  await ctx.subscribe("nmqtt", 2, on_data)

proc mqttPub() {.async.} =
  await ctx.start()
  await ctx.publish("nmqtt", "hallo", 2)
  await sleepAsync 500
  await ctx.disconnect()

proc mqttSubPub() {.async.} =
  await ctx.start()

  # Callback when receiving on the topic
  proc on_data(topic: string, message: string) =
    echo "got ", topic, ": ", message
  
  # Subscribe to topic
  await ctx.subscribe("nmqtt", 2, on_data)
  await sleepAsync 500

  # Publish a message to the topic `nmqtt`
  await ctx.publish("nmqtt", "hallo", 2)
  await sleepAsync 500

  # Disconnect
  await ctx.disconnect()

#asyncCheck mqttSub
#runForever()
# OR
#waitFor mqttPub()
# OR
#waitFor mqttSubPub()
```


# Procs

## newMqttCtx*

```nim
proc newMqttCtx*(clientId: string): MqttCtx =
```

Initiate a new MQTT client


____

## set_ping_interval*

```nim
proc set_ping_interval*(ctx: MqttCtx, txInterval: int) =
```

Set the clients ping interval in seconds. Default is 60 seconds.


____

## set_host*

```nim
proc set_host*(ctx: MqttCtx, host: string, port: int=1883, doSsl=false) =
```

Set the MQTT host


____

## set_auth*

```nim
proc set_auth*(ctx: MqttCtx, username: string, password: string) =
```

Set the authentication for the host


____

## connect*

```nim
proc connect*(ctx: MqttCtx) {.async.} =
```

Connect to the broker.


____

## isConnected*

```nim
proc isConnected*(ctx: MqttCtx): bool =
```

Returns true, if the client is connected to the broker.


____

## start*

```nim
proc start*(ctx: MqttCtx) {.async.} =
```

Auto-connect and reconnect to the broker. The client will try to
reconnect when the state is `Disconnected` or `Error`. The `Error`-state
happens, when the broker is down, but the client will try to reconnect
until the broker is up again.


____

## disconnect*

```nim
proc disconnect*(ctx: MqttCtx) {.async.} =
```

Disconnect from the broker.


____

## publish*

```nim
proc publish*(ctx: MqttCtx, topic: string, message: string, qos=0, retain=false) {.async.} =
```

Publish a message


____

## subscribe*

```nim
proc subscribe*(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback): Future[void] =
```

Subscribe to a topic


____


## unsubscribe*

```nim
proc unsubscribe*(ctx: MqttCtx, topic: string): Future[void] =
```

Unubscribe from a topic.

Access the callback with:
```nim
proc callbackName(topic: string, message: string) =
  echo "Topic: ", topic, ": ", message
```


____