# nmqtt_broker - WIP
MQTT broker based upon the Nim library [nmqtt](https://github.com/zevv/nmqtt).

Not used code from [nmqtt](https://github.com/zevv/nmqtt) is just commented out.
What to do with it is unclear.


# Run

Currently it spins the broker at `127.0.0.1:1883`.

```nim
nim c -d:release -r src/nmqtt_broker
```
or
```nim
nimble build
src/nmqtt_broker
#
nimble install
nmqtt_broker
```

# TODO

## Structure of code

How should the code be structured? Currently all broker code is included, and at the specific cases, where it breaks the normal library code `when defined(broker)` is used. At places where the code does not break a `#when defined(broker):` is inserted.

But the above results in, that we are carrying more fields around in the client `ctx: MqttCtx`. E.g. the proto, version, subscribed - which are only used in the normal library.

Please give inputs!

Possible methods:
* Current method. Include all code and accept that we might use a little more size and performance.
* Encapsule all in `when defined(broker)` and go against DRY
* Divide the the main file into multiple files. That would still require to break a little DRY.


## table changed while iterating

Thousands of parallel connections - subscribe and publish - causes a problem....

`Error: unhandled exception: tables.nim(667, 13) len(t) == L the length of the table changed while iterating over it [AssertionError]`


## MQTT specifications

There's a lot of things, but these are first priority.

* Disconnect client after 1,5 time the `keepAlive` time
* Retain
* Wildcards in topics: `+`
* Clean Session


## Configuration file/CLI-options

A configuration file and CLI-options.


## Password check

An implementation for a hash and salt passwords like Mosquitto.


## msgId in PingResp

`PingResp` is added to the `workQueue`, which requires the packet to be assigned
with a `msgId`. We are using a _fake_ `msgId`...
Currently using the next `msgId + 1000`. This works, but if the same client
sends 1000's packets we could hit a break. To prevent this we are using
`hasKey()`, which needs to be removed. Another solution would be to assign
`0`, but what if we encounter 1000's of `Publish` and `PingReq` at the same
time?

```nim
while ctx.workQueue.hasKey(msgId):
  msgId += 1000
```


# Performance

These benchmarks are made on a machine, which was running multiple other programs
and using the internet during the test. They are not valid results, and therefor
just used in my development process.

The benchmark was done with [mqtt-bench](https://github.com/takanorig/mqtt-bench).
It should be noted that `nmqtt_broker` is faster than  `mosquitto` to receive
the `Publish`, but **not** at handling them.

## Publish results

| broker       | packetsize | clients | totalcount | duration | throughput       |
|--------------|------------|---------|------------|----------|------------------|
| nmqtt_broker | 4096       | 25      | 25000      | 313 ms   | 79872.20 msg/sec |
| mosquitto    | 4096       | 25      | 25000      | 357 ms   | 70028.01 msg/sec |
| nmqtt_broker | 1024       | 25      | 25000      | 166 ms   | 150602.41 msg/sec |
| mosquitto    | 1024       | 25      | 25000      | 191 ms   | 130890.05 msg/sec |

```bash
# Size 4096
./mqtt-bench -action=p -broker="tcp://127.0.0.1:1883" -count 1000 -clients 25 -size 4096
# Size 1024
./mqtt-bench -action=p -broker="tcp://127.0.0.1:1883" -count 1000 -clients 25 -size 1024
```

## Subscribe results

| broker       | packetsize | clients | totalcount | duration | throughput       |
|--------------|------------|---------|------------|----------|------------------|
| nmqtt_broker | 4096       | 25      | 1060       | 242 ms   | 4380.17 msg/sec  |
| mosquitto    | 4096       | 25      | 2871       | 50 ms    | 57420.00 msg/sec |


```bash
# Run at the same time in 2 terminals in this order
./mqtt-bench -broker="tcp://127.0.0.1:1883" -action=pub -count 100000 -intervaltime=2
./mqtt-bench -broker="tcp://127.0.0.1:1883" -action=sub -intervaltime=2
```