kafka_0.6_replicator (krepl)
============================

krepl is an Erlang application to continuously replicate a set of topics from one kafka 0.6 broker to another.

# Prerequisites

In order to use krepl, you need two kafka brokers (source and target) and a redis instance to keep offsets.

# Building

```
git clone git@github.com:wooga/kafka_0.6_replicator.git
cd kafka_0.6_replicator
make
```

To install zsh completion for `bin/krepl`:
```
sudo make completion
```

# Configuration

`config/krepl.config`

```
[
    {lager, [
        {handlers, [
            {lager_console_backend, info},
            {lager_file_backend, [{file, "log/error.log"}, {level, error}]},
            {lager_file_backend, [{file, "log/console.log"}, {level, info}]}
    ]}]},
    {krepl, [
        {redis_host, "127.0.0.1"},
        {redis_port, 6379},

        {initial_offset_source, target},

        % from live to dev
        {handler_name, "live_to_dev"},
        {source_host, "kafka.sys11"},
        {source_port, 9092},
        {target_host, "127.0.0.1"},
        {target_port, 9092},

        {pool_size, 5},
        {topics, [
         "ahi",
         {"bi", "bi_dup"},
         "bim",
         "bri"
        ]}
    ]}

].
```

The config file defines where redis and the two kafkas live and which topics should be replicated (either as a string or a 2-tuple {source, target}). `handler_name` is the identifier of the replicator used in redis.

The value of `initial_offset_source` defines where krepl starts replicating. The value `source` is used when to start at the sources newest offset. With `target` it uses the newest target offset, which only makes sense when the offsets of both source and target are equivalent (pointing to the same data).

`local_to_local` is the example handler name here.

# Starting, Stopping etc.

All important functions are called via `bin/krepl`.

## Resetting Offsets

Before starting, the offsets have to be (re)set. You have different options:

Reset to most latest offsets (Head):

`./bin/krepl reset_offsets local_to_local`

Reset to earliest offsets:

`./bin/krepl reset_to_oldest_offsets local_to_local`

Reset all offsets to 0:

`./bin/krepl zero_offsets local_to_local`

Reset an offset for a single topic:

`./bin/krepl reset_single_offset local_to_local the_topic 123`


Reset offsets from a JSON file with the structure

```
{"results":[{"topic":"ahi","offset":2732945670},{"topic":"pla","offset":18992525,}]}
```

`./bin/krepl reset_offsets_from_file local_to_local offsets.json`

This can be used with the output from [kafka_bisect](https://github.com/wooga/kafka_bisect).


## Starting and attaching

You can either start krepl as a daemon: `bin/krepl start local_to_local`

Or you can start it in a console: `bin/krepl console local_to_local`

Use `bin/krepl attach local_to_local` to attach to a running node (use ctrl-c ctrl-c to detach).

## Stopping

`bin/krepl stop local_to_local`

## Status

`bin/krepl status local_to_local` shows the current offsets and lags for each topic.

```
replicator 'live_to_dev' from kafka.sys11:9092 to 127.0.0.1:9092
ahi        ->    ahi          2732945670 Offset         0 MB lag
bi         ->    bi_dup    4463104280542 Offset      1672 MB lag
bim        ->    bim       1172574050123 Offset         0 MB lag
bri        ->    bri           425740700 Offset         0 MB lag

Total lag: 1753219072 Bytes
```

## Adding topics

In order to add topics add them to the config and then stop and start the application.

## krepl internals

### Application structure

![supervision tree](../master/doc/supervision_tree.png?raw=true "supervision tree")

The root supervisor `krepl_sup` (a [supervisor2](https://github.com/odo/supervisor2)) has two children:

* `krepl_redis` is a [redis server](https://github.com/wooga/eredis) which is used by the adapters to write their current offsets.

* `krepl_adapter_sup` supervises a set of `krepl_adapter` processes, one for each topic. Each `krepl_adapter` process has one [consumer server](https://github.com/wooga/kafka-erlang/blob/master/src/kafka_consumer.erl) to retrieve massages from the source kafka broker and one [producer server](https://github.com/wooga/kafka-erlang/blob/master/src/kafka_producer.erl) to write messages to the target kafka.

`krepl_adapter` processes are the prime movers of the system passing through a loop:

1. get new messages and current offset from attached consumer
* write messages to producer
* write current offset to redis
* repeat

### Resilience

For any type of failure (internal exception, connection error to one of the kafkas or redis) there are three levels of recovery:

A: The process that exited is restarted by its supervisor and tries to resume its task.


If (A) fails a number of times (e.g. 100 times in 10 seconds) the supervisor of the failing process dies and escalates the problem to `krepl_sup`.

B: `krepl_sup` will stop all processes of the applications and tries to restart everything in order.

If (B) fails a number of times (e.g. 100 times in 10 seconds):

C: 'krepl_sup' will fall back to restarting everything every 10 seconds. Forever.
