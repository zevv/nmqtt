# Native Nim MQTT client library

This is a hybrid package including a native Nim MQTT library and
binaries for publishing and subscribing to a MQTT-broker.

* [Install](#Install)
* [Binaries](#Binaries)
  * [Publish](#Publish)
  * [Subscribe](#Subscribe)
* [Library](#Library)
  * [Examples](#Examples)
  * [Procs](#Procs)


# Install

You can install this package with Nimble:
```nim
$ nimble install nmqtt
```

or cloning and installing:
```nim
$ git clone https://github.com/zevv/nmqtt.git && cd nmqtt
$ nimble install
```

# Binaries

The package provides 2 binaries for publishing messages to a MQTT-broker and
for subscribing to a MQTT-broker.

## Publish
```bash
$ ./nmqtt_pub --help
Publish MQTT messages to a MQTT-broker.

Usage:
  nmqtt_pub [options] -t {topic} -m {message}
  nmqtt_pub [-h host -p port -u username -P password] -t {topic} -m {message}

OPTIONS
  -?, --help        print this cligen-erated help
  --help-syntax     advanced: prepend,plurals,..
  -h=, --host=      IP-address of the broker.
  -p=, --port=      network port to connect too.
  --ssl             enable ssl. Auto-enabled on port 8883.
  -c=, --clientid=  your connection ID. Defaults to nmqtt_pub_ appended with processID.
  -u=, --username=  provide a username
  -P=, --password=  provide a password
  -t=, --topic=     MQTT topic to publish to.
  -m=, --msg=       set msg
  -q=, --qos=       quality of service level to use for all messages.
  -r, --retain      retain messages on the broker.
  --willtopic=      set the will's topic
  --willmsg=        set the will's message
  --willqos=        set the will's quality of service
  --willretain      set to retain the will message
  -v, --verbose     set verbose
```

_`-verbose` not implemented yet_


## Subscribe
```bash
$ ./nmqtt_sub --help
Subscribe to a topic on a MQTT-broker.

Usage:
  nmqtt_sub [options] -t {topic}
  nmqtt_sub [-h host -p port -u username -P password] -t {topic}

OPTIONS
  -?, --help        print this cligen-erated help
  --help-syntax     advanced: prepend,plurals,..
  -h=, --host=      IP-address of the broker.
  -p=, --port=      network port to connect too.
  --ssl             enable ssl. Auto-enabled on port 8883.
  -c=, --clientid=  your connection ID. Defaults to nmqtt_pub_ appended with processID.
  -u=, --username=  provide a username
  -P=, --password=  provide a password
  -t=, --topic=     MQTT topic to publish to.
  -q=, --qos=       quality of service level to use for all messages.
  --willtopic=      set the will's topic
  --willmsg=        set the will's message
  --willqos=        set the will's quality of service
  --willretain      set to retain the will message
  -v, --verbose     set verbose
```

_`-verbose` not implemented yet_


# Library

This library includes all the needed proc's for publishing MQTT messages to
a MQTT-broker and for subscribing to a topic on a MQTT-broker. The library supports QOS 1, 2 and 3 for both publishing and subscribing and sending retained messages.

## Examples

### Subscribe to topic
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

asyncCheck mqttSub
runForever()
```

### Publish msg
```nim
proc mqttPub() {.async.} =
  await ctx.start()
  await ctx.publish("nmqtt", "hallo", 2)
  await sleepAsync 500
  await ctx.disconnect()

waitFor mqttPub()
```

### Subscribe and publish
```nim
proc mqttSubPub() {.async.} =
  await ctx.start()

  # Callback when receiving on the topic
  proc on_data(topic: string, message: string) =
    echo "got ", topic, ": ", message

  # Subscribe to topic the topic `nmqtt`
  await ctx.subscribe("nmqtt", 2, on_data)
  await sleepAsync 500

  # Publish a message to the topic `nmqtt`
  await ctx.publish("nmqtt", "hallo", 2)
  await sleepAsync 500

  # Disconnect
  await ctx.disconnect()

waitFor mqttSubPub()
```



## Procs

### newMqttCtx*

```nim
proc newMqttCtx*(clientId: string): MqttCtx =
```

Initiate a new MQTT client


____

### set_ping_interval*

```nim
proc set_ping_interval*(ctx: MqttCtx, txInterval: int) =
```

Set the clients ping interval in seconds. Default is 60 seconds.


____

### set_host*

```nim
proc set_host*(ctx: MqttCtx, host: string, port: int=1883, doSsl=false) =
```

Set the MQTT host


____

### set_auth*

```nim
proc set_auth*(ctx: MqttCtx, username: string, password: string) =
```

Set the authentication for the host


____

### set_will*

```nim
proc set_will*(ctx: MqttCtx, topic, msg: string, qos=0, retain=false) =
```

Set the clients will.


____

### connect*

```nim
proc connect*(ctx: MqttCtx) {.async.} =
```

Connect to the broker.


____

### start*

```nim
proc start*(ctx: MqttCtx) {.async.} =
```

Auto-connect and reconnect to the broker. The client will try to
reconnect when the state is `Disconnected` or `Error`. The `Error`-state
happens, when the broker is down, but the client will try to reconnect
until the broker is up again.


____

### disconnect*

```nim
proc disconnect*(ctx: MqttCtx) {.async.} =
```

Disconnect from the broker.


____

### publish*

```nim
proc publish*(ctx: MqttCtx, topic: string, message: string, qos=0, retain=false) {.async.} =
```

Publish a message.

**Required:**
  - topic: string
  - message: string

**Optional:**
  - qos: int     = 1, 2 or 3
  - retain: bool = true or false

**Publish message:**
```nim
ctx.publish(topic = "nmqtt", message = "Hey there", qos = 0, retain = true)
```

**Remove retained message on topic:**

Set the `message` to _null_.
```nim
ctx.publish(topic = "nmqtt", message = "", qos = 0, retain = true)
```


____

### subscribe*

```nim
proc subscribe*(ctx: MqttCtx, topic: string, qos: int, callback: PubCallback): Future[void] =
```

Subscribe to a topic

Access the callback with:
```nim
proc callbackName(topic: string, message: string) =
  echo "Topic: ", topic, ": ", message
```

____


### unsubscribe*

```nim
proc unsubscribe*(ctx: MqttCtx, topic: string): Future[void] =
```

Unubscribe from a topic.


____

### isConnected*

```nim
proc isConnected*(ctx: MqttCtx): bool =
```

Returns true, if the client is connected to the broker.


____

### msgQueue*

```nim
proc msgQueue*(ctx: MqttCtx): int =
```

Returns the number of unfinished packages, which still are in the work queue.
This includes all publish and subscribe packages, which has not been fully
send, acknowledged or completed.

You can use this to ensure, that all your of messages are sent, before
exiting your program.


____