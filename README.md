kafka_ductus
============================

kafka_ductus is an Erlang application to consume messages from kafka.

It fetches messages (1MB at a time) from a set of topics from kafka, parses the mesages for you and feeds them into your callback module.

tl;dr here is an example [kafka2file](https://github.com/odo/kafka2file).

# Prerequisites

You need:

1. [Erlang](http://erlang.org)
* A [kafka 0.6](http://sna-projects.com/kafka/downloads.php) broker you want to read from
* A [redis](http://redis.io) server to save state

# Building

```
git clone git@github.com:odo/kafka_ductus.git
cd kafka_ductus
make
```

# Configuration

kafka_ductus uses [erlconf](https://github.com/wooga/erlconf) so you have `/config/default.conf` for your base configuration and `conf/{your_config}.conf` for the more specific stuff.

`config/examples.config`:

```
[
    {ductus, [
        {source_host, "kafka-primary.acc"},
        {source_port, 9092},

        {redis_host, "127.0.0.1"},
        {redis_port, 6379},

        {initial_offset_source, source},

        {handler_name, "kafka_ductus"},
        {periodic_period, 10000}
        {callback_module, ductus_example_handler},
        {topics, [
         {"test", {}}
        ]}
    ]}
].
```

* `source_host`, `source_port`: the kafka you are reading from
* `redis_host`, `redis_port`: redis
* `handler_name`: used to name the node and as a key for redis
* `callback_module`: the name of your callback module
* `periodic_period`: the time between calls to `handle_periodic_aggregate` in your callback module
* `topics`: a list of topics in the form of `{topic_name, handler_init_data}`

# Starting, Stopping etc.

All important functions are called via `bin/ductus`.

## Resetting Offsets

Before starting, the offsets have to be (re)set. You have different options (`local_to_local` is your config in this example):

Reset to most recent offsets (Head):

`./bin/ductus reset_offsets local_to_local`

Reset to earliest/latest available offsets:

`./bin/ductus reset_to_oldest_offsets local_to_local`

Reset all offsets to 0:

`./bin/ductus zero_offsets local_to_local`

Reset an offset for a single topic:

`./bin/ductus reset_single_offset local_to_local the_topic 123`


Reset offsets from a JSON file with the structure

```
{"results":[{"topic":"topic1","offset":2732945670},{"topic":"topic2","offset":18992525,}]}
```

`./bin/ductus reset_offsets_from_file local_to_local offsets.json`

This can be used with the output from [kafka_bisect](https://github.com/wooga/kafka_bisect).


## Starting and attaching

You can either start ductus as a daemon: `bin/ductus start local_to_local`

Or you can start it in a console: `bin/ductus console local_to_local`

Use `bin/ductus attach local_to_local` to attach to a running node (use ctrl-c ctrl-c to detach).

## Stopping

`bin/ductus stop local_to_local`

## Status

`bin/ductus status local_to_local` shows the current offsets and lags for each topic.

```
kafka_ductus 'kafka_ductus' from kafka-primary.acc:9092
test      :          10253927224 Offset      3405 MB lag

Total lag: 3570864347 Bytes
```

## Adding topics

In order to add topics add them to the config and then stop the application, set the offset for the new topics and start the application.

## The callback module

your application logic lives in a callback module which must implement the `ductus_callback` behaviour:

* `init/2` is used to init the state of your handler. Arguments are the topic name and the init data specified in the config file. The return value must be {ok, State}.

* `handle_massages/3` is called with a set of massages (~ 1 MB), the current kafka offset and your callback's state. The return value must be {ok, State}.

* `aggregate_element/1` is called with your callback's state. It is used to periodicly collect data from all adapters. Returns {ok, Element, State}.

* `handle_periodic_aggregate` is called with an orddict where the keys are the topic names (in binary) and values are the elements returned by `aggregate_element/1`. The return value is ignored.

## ductus internals

### Application structure

![supervision tree](../master/doc/supervision_tree.png?raw=true "supervision tree")

The root supervisor `ductus_sup` (a [supervisor2](https://github.com/odo/supervisor2)) has three children:

* `ductus_adapter_sup` supervises a set of `ductus_adapter` processes, one for each topic. Each `ductus_adapter` process has one [consumer server](https://github.com/wooga/kafka-erlang/blob/master/src/kafka_consumer.erl) to retrieve massages from the kafka broker.

* `ductus_perodic` aggregates data from all topics and passes it to the function `handle_periodic_aggregate/1` in your callback module.

* `ductus_redis` is a [redis server](https://github.com/wooga/eredis) which is used by the adapters to write their current offsets.

`ductus_adapter` processes are the prime movers of the system passing through a loop:

1. get new messages and current offset from attached consumer
* pass messages to callback module and wait for return
* write current offset to redis
* repeat

### Resilience

For any type of failure (internal exception, connection error to one of the kafkas or redis) there are three levels of recovery:

A: The process that exited is restarted by its supervisor and tries to resume its task.


If (A) fails a number of times (e.g. 100 times in 10 seconds) the supervisor of the failing process dies and escalates the problem to `ductus_sup`.

B: `ductus_sup` will stop all processes of the applications and tries to restart everything in order.

If (B) fails a number of times (e.g. 100 times in 10 seconds):

C: 'ductus_sup' will fall back to restarting everything every 10 seconds. Forever.

