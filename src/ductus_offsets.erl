-module(ductus_offsets).

-compile(export_all).

offset(Topic) when is_binary(Topic) ->
    offset(binary_to_list(Topic));
offset(Topic) ->
    {ok, Offset} = eredis:q(ductus_redis, ["HGET", ductus:handler_name(), Topic]),
    case Offset of
        undefined ->
            throw({error, {cound_not_get_offset, Topic}});
        _ ->
            list_to_integer(binary_to_list(Offset))
    end.

set_offset({ConsumerTopic, _}, Offset) ->
    set_offset(ConsumerTopic, Offset);
set_offset(Topic, Offset) when is_binary(Topic) ->
    set_offset(binary_to_list(Topic), Offset);
set_offset(Topic, Offset) ->
    eredis:q(ductus_redis, ["HSET", ductus:handler_name(), Topic, Offset]).

offset_from_kafka(Topic, Consumer, NewestOrOldest) ->
    NewestOrOldestInt =
    proplists:get_value(NewestOrOldest, [{newest, -1}, {oldest, -2}]),
    parse_kafka_offset(Topic, kafka_consumer:get_offsets(Consumer, NewestOrOldestInt, 1)).

parse_kafka_offset(_, {ok, [Offset]}) ->
    Offset;
parse_kafka_offset(Topic, Other) ->
    throw({error, {cound_not_get_kafka_offset, {Topic, Other}}}).

reset_offset() ->
    reset_offsets(newest).

reset_to_oldest_offsets() ->
    reset_offsets(oldest).

reset_offsets(NewestOrOldest) ->
    {Host, Port} = case erlconf:get_value(ductus, initial_offset_source) of
        source ->
            {erlconf:get_value(ductus, source_host),
             erlconf:get_value(ductus, source_port)};
        target ->
            {erlconf:get_value(ductus, target_host),
             erlconf:get_value(ductus, target_port)}
    end,
    lager:info("resetting offsets for ~p from kafka at ~p:~p\n", [ductus:handler_name(), Host, Port]),
    Topics = erlconf:get_value(ductus, topics),
    [reset_offset(Topic, Host, Port, NewestOrOldest) || Topic <- Topics].

reset_offset(Topic, Host, Port, NewestOrOldest) when is_list(Topic) ->
    reset_offset({Topic, Topic}, Host, Port, NewestOrOldest);

reset_offset({SourceTopic, _}, Host, Port, NewestOrOldest) ->
    {ok, Consumer} = kafka_consumer:start_link(
        Host, Port, list_to_binary(SourceTopic), 0, 0, fun(_, _, _) -> noop end, 10000),
    Offset = offset_from_kafka(SourceTopic, Consumer, NewestOrOldest),
    lager:info("setting offset for ~p \tto ~p\n", [SourceTopic, Offset]),
    unlink(Consumer),
    exit(Consumer, kill),
    set_offset(SourceTopic, Offset).

zero_offsets() ->
    Topics = erlconf:get_value(ductus, topics),
    [set_offset(Topic, 0) || Topic <- Topics].
