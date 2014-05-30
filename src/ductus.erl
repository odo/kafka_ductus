-module(ductus).
-export([start/0, handler_name/0, running/0, status/0, request_status/3,
         zero_offsets/0, reset_offsets/0, reset_to_oldest_offsets/0, reset_offsets_from_file/1, reset_single_offset/2]).

start() ->
    application:start(sasl),
    lager:start(),
    erlconf:load(ductus),
    application:start(ductus).

handler_name() ->
    {ok, HandlerName} = application:get_env(ductus, handler_name),
    HandlerName.

running() ->
    Apps = proplists:get_keys(application:which_applications()),
    lists:member(ductus, Apps).

status() ->
    SourceHost = erlconf:get_value(ductus, source_host),
    SourcePort = erlconf:get_value(ductus, source_port),
    Repl = io_lib:format("kafka_ductus '~s' from ~s:~s\n",
         [ductus:handler_name(), SourceHost, integer_to_list(SourcePort)]),
    Status = case whereis(ductus_adapter_sup) of
        undefined ->
            "Error: Adapter supervisor not running.";
        _ ->
            Pids = [Pid || {_, Pid, _, _} <- supervisor:which_children(ductus_adapter_sup), is_pid(Pid)],
            case Pids of
                [] ->
                    "Error: Adapter supervisor has no children.";
                _ ->
                    Statuses           = collect_statuses(Pids),
                    StatusesNoTimeouts = [S || S <- Statuses, S =/= timeout],
                    case StatusesNoTimeouts of
                        [] ->
                            "Error: No adpaters running.";
                        _ ->
                            {OffsetDiffs, StatusLines} = lists:unzip(StatusesNoTimeouts),
                            string:join(lists:sort(StatusLines), "") ++
                            "\nTotal lag: " ++ integer_to_list(lists:sum(OffsetDiffs)) ++ " Bytes"
                    end
            end
        end,
        lists:flatten(Repl) ++ Status.

collect_statuses(Pids) ->
    Ref = make_ref(),
    [spawn(?MODULE, request_status, [self(), Ref, Pid]) || Pid <- Pids],
    [collect_status(Ref) || _ <- Pids].


request_status(From, Ref, Pid) ->
    Status = ductus_adapter:status(Pid),
    From ! {Ref, Status}.

collect_status(Ref) ->
    receive
        {Ref, Status} -> Status
    after 500 ->
        timeout
    end.

reset_offsets() ->
    prepare_for_reset(),
    ductus_offsets:reset_offsets().

reset_to_oldest_offsets() ->
    prepare_for_reset(),
    ductus_offsets:reset_to_oldest_offsets().

reset_offsets_from_file(Filename) ->
    prepare_for_reset(),
    {ok, Json} = file:read_file(Filename),
    Struct     = ductus_json:decode(Json),
    Results    = orddict:fetch(<<"results">>, Struct),
    [ductus_offsets:set_offset(orddict:fetch(<<"topic">>, Res),
                              orddict:fetch(<<"offset">>, Res))
     || Res <- Results].

reset_single_offset(Topic, Offset) ->
    prepare_for_reset(),
    ductus_offsets:set_offset(list_to_binary(Topic), list_to_integer(Offset)).

zero_offsets() ->
    prepare_for_reset(),
    ductus_offsets:zero_offsets().

prepare_for_reset() ->
    erlconf:load(ductus),
    lager:start(),
    start_redis().

start_redis() ->
    RedisHost = erlconf:get_value(ductus, redis_host),
    RedisPort = erlconf:get_value(ductus, redis_port),
    ductus_redis:start_link(ductus_redis, RedisHost, RedisPort).

