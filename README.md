# Native Nim MQTT client library and binaries

This is a hybrid package including a native Nim MQTT library and
binaries for a MQTT broker, publisher and subscriber.

* [Install](#Install)
* [Binaries](#Binaries)
  * [nmqtt](#nmqtt)
  * [nmqtt_password](#nmqtt_password)
  * [nmqtt_pub](#nmqtt_pub)
  * [nmqtt_sub](#nmqtt_sub)
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

The package provides 4 MQTT binaries:
1) `nmqtt` -> Broker
2) `nmqtt_password` -> Password utility for the broker
3) `nmqtt_pub` -> MQTT publisher
4) `nmqtt_sub` -> MQTT subscriber


## nmqtt

A default configuration file is provided in `config/nmqtt.conf`. You can copy and paste this file to a desired location, or run `nimble setup nmqtt` which will guide you through it.

```
$ nmqtt --help
nmqtt version 1.0.0

nmqtt is a MQTT v3.1.1 broker

USAGE
  nmqtt [options]
  nmqtt [-c /path/to/config.conf]
  nmqtt [-h hostIP -p port]

CONFIG
  Use the configuration file for detailed settings,
  such as SSL, adjusting keep alive timer, etc. or
  specify options at the command line.

  To add and delete users from the password file
  please use nmqtt_password:
    - nmqtt_password -a|-b|-d [options]

OPTIONS
  -?, --help          print this cligen-erated help
  -c=, --config=      absolute path to the config file. Overrides all other options.
  -h=, --host=        IP-address to serve the broker on.
  -p=, --port=        network port to accept connecting from.
  -v=, --verbosity=   verbosity from 0-3.
  --max-conn=         max simultaneous connections. Defaults to no limit.
  --clientid-maxlen=  max lenght of clientid. Defaults to 65535.
  --clientid-spaces   allow spaces in clientid. Defaults to false.
  --clientid-empty    allow empty clientid and assign random id. Defaults to false.
  --client-kickold    kick old client, if new client has same clientid. Defaults to false.
  --clientid-pass     pass clientid in payload {clientid:payload}. Defaults to false.
  --password-file=    absolute path to the password file
  --ssl               activate ssl for the broker - requires --ssl-cert and --ssl-key.
  --ssl-cert=         absolute path to the ssl certificate.
  --ssl-key=          absolute path to the ssl key.
```


## nmqtt_password
```
$ nmqtt_password --help
nmqtt_password is a user and password manager for nmqtt
nmqtt_password is based upon nmqtt version 1.0.0

USAGE
  nmqtt_password -a {password_file.conf} {username}
  nmqtt_password -b {password_file.conf} {username} {password}
  nmqtt_password -d {password_file.conf} {username}

CONFIG
  Add or delete users from nmqtt password file.

OPTIONS
  -?, --help     print this cligen-erated help
  -a, --adduser  add a new user to the password file.
  -b, --batch    run in batch mode to allow passing passwords on the command line.
  -d, --deluser  delete a user from the password file.
```


## nmqtt_pub
```
$ ./nmqtt_pub --help
nmqtt_pub is a MQTT client for publishing messages to a MQTT-broker.
nmqtt_pub is based upon nmqtt version 1.0.0

Usage:
  nmqtt_pub [options] -t {topic} -m {message}
  nmqtt_pub [-h host -p port -u username -P password] -t {topic} -m {message}

OPTIONS
  -?, --help         print this cligen-erated help
  -h=, --host=       IP-address of the broker.
  -p=, --port=       network port to connect too.
  --ssl              use ssl.
  -c=, --clientid=   your connection ID. Defaults to nmqttpub- appended with processID.
  -u=, --username=   provide a username
  -P=, --password=   provide a password
  -t=, --topic=      mqtt topic to publish to.
  -m=, --msg=        message payload to send.
  -q=, --qos=        quality of service level to use for all messages.
  -r, --retain       retain messages on the broker.
  --repeat=          repeat the publish N times.
  --repeatdelay=     if using --repeat, wait N seconds between publish. Defaults to 0.
  --willtopic=       set the will's topic
  --willmsg=         set the will's message
  --willqos=         set the will's quality of service
  --willretain       set to retain the will message
  -v=, --verbosity=  set the verbosity level from 0-2. Defaults to 0.
```


## nmqtt_sub
```
$ ./nmqtt_sub --help
nmqtt_sub is a MQTT client that will subscribe to a topic on a MQTT-broker.
nmqtt_sub is based upon nmqtt version 1.0.0

Usage:
  nmqtt_sub [options] -t {topic}
  nmqtt_sub [-h host -p port -u username -P password] -t {topic}

OPTIONS
  -?, --help         print this cligen-erated help
  -h=, --host=       IP-address of the broker. Defaults to 127.0.0.1
  -p=, --port=       network port to connect too. Defaults to 1883.
  --ssl              use ssl.
  -c=, --clientid=   your connection ID. Defaults to nmqttsub- appended with processID.
  -u=, --username=   provide a username
  -P=, --password=   provide a password
  -t=, --topic=      MQTT topic to subscribe too. For multipe topics, separate them by comma.
  -q=, --qos=        quality of service level to use for all messages. Defaults to 0.
  -k=, --keepalive=  keep alive in seconds for this client. Defaults to 60.
  --removeretained   clear any retained messages on the topic
  --willtopic=       set the will's topic
  --willmsg=         set the will's message
  --willqos=         set the will's quality of service
  --willretain       set to retain the will message
  -v=, --verbosity=  set the verbosity level from 0-2. Defaults to 0.
```


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
#ctx.set_ssl_certificates("cert.crt", "private.key")

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

### set_ssl_certificates*

```nim
proc set_ping_interval*(ctx: MqttCtx, sslCertFile: string, sslKeyFile: string) =
```

Sets the SSL Certificate and Key files to use Mutual TLS authentication

____

### set_host*

```nim
proc set_host*(ctx: MqttCtx, host: string, port: int=1883, sslOn=false) =
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
  - qos: int     = 0, 1 or 2
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