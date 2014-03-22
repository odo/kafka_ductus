-module(krepl).
-export([start/0, handler_name/0, running/0, status/0, request_status/3,
         zero_offsets/0, reset_offsets/0, reset_to_oldest_offsets/0, reset_offsets_from_file/1, reset_single_offset/2]).

start() ->
    application:start(sasl),
    lager:start(),
    erlconf:load(krepl),
    %application:start(reconnaissance),
    %stop_if_conflicting_replication(),
    application:start(krepl).

stop_if_conflicting_replication() ->
    case krepl_reconnaissance:other_nodes_with_same_config() of
        [] ->
            noop;
        Others  ->
            Report = fun({IP, HandlerName, CommonSet}) ->
                lager:error("~s on ~p also replicating (showing both directions):\n", [HandlerName, IP]),
                [lager:error("~p:~p:~p -> ~p:~p:~p\n", [SH, SP, ST, TH, TP, TT])
                    || {{SH, SP, ST}, {TH, TP, TT}} <- sets:to_list(CommonSet)]
            end,
            lager:error("\n\n***Found conflicting krepl replicator:***\n", []),
            lists:foreach(Report, Others),
            lager:error("stopping.\n", []),
            init:stop()
    end.

handler_name() ->
    {ok, HandlerName} = application:get_env(krepl, handler_name),
    HandlerName.

running() ->
    Apps = proplists:get_keys(application:which_applications()),
    lists:member(krepl, Apps).

status() ->
    SourceHost = erlconf:get_value(krepl, source_host),
    SourcePort = erlconf:get_value(krepl, source_port),
    TargetHost = erlconf:get_value(krepl, target_host),
    TargetPort = erlconf:get_value(krepl, target_port),
    Repl = io_lib:format("replicator '~s' from ~s:~s to ~s:~s\n",
         [krepl:handler_name(), SourceHost, integer_to_list(SourcePort), TargetHost, integer_to_list(TargetPort)]),
    Status = case whereis(krepl_adapter_sup) of
        undefined ->
            "Error: Adapter supervisor not running.";
        _ ->
            Pids = [Pid || {_, Pid, _, _} <- supervisor:which_children(krepl_adapter_sup), is_pid(Pid)],
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
    Status = krepl_adapter:status(Pid),
    From ! {Ref, Status}.

collect_status(Ref) ->
    receive
        {Ref, Status} -> Status
    after 500 ->
        timeout
    end.

reset_offsets() ->
    prepare_for_reset(),
    krepl_offsets:reset_offsets().

reset_to_oldest_offsets() ->
    prepare_for_reset(),
    krepl_offsets:reset_to_oldest_offsets().

reset_offsets_from_file(Filename) ->
    prepare_for_reset(),
    {ok, Json} = file:read_file(Filename),
    Struct     = krepl_json:decode(Json),
    Results    = orddict:fetch(<<"results">>, Struct),
    [krepl_offsets:set_offset(orddict:fetch(<<"topic">>, Res),
                              orddict:fetch(<<"offset">>, Res))
     || Res <- Results].

reset_single_offset(Topic, Offset) ->
    prepare_for_reset(),
    krepl_offsets:set_offset(list_to_binary(Topic), list_to_integer(Offset)).

zero_offsets() ->
    prepare_for_reset(),
    krepl_offsets:zero_offsets().

prepare_for_reset() ->
    erlconf:load(krepl),
    lager:start(),
    start_redis().

start_redis() ->
    RedisHost = erlconf:get_value(krepl, redis_host),
    RedisPort = erlconf:get_value(krepl, redis_port),
    krepl_redis:start_link(krepl_redis, RedisHost, RedisPort).

