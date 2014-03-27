-module(ductus_example_handler).

-behaviour(ductus_callback).

-export([init/2, handle_messages/3, aggregate_element/1, handle_periodic_aggregate/1]).

-record(state, { topic, last_batch_timelag }).

-define(SECONDS1970, calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}})).

init(Topic, InitData) ->
    io:format("init: ~p\n", [{Topic, InitData}]),
    {ok, #state{ topic = Topic }}.

handle_messages([], _Offset, State) ->
    {ok, State#state{ last_batch_timelag = 0}};

handle_messages(Msgs, _Offset, State) ->
    FirstMessage   = hd(Msgs),
    [_, TSBin | _] = binary:split(binary_part(FirstMessage, {0, min(byte_size(FirstMessage), 100)}), <<" ">>, [global]),
    Timestamp      = list_to_integer(binary_to_list(TSBin)),
    Datetime       = calendar:now_to_universal_time(os:timestamp()),
    SecondsNow     = calendar:datetime_to_gregorian_seconds(Datetime) - ?SECONDS1970,
    LastBatchTimelag = SecondsNow - Timestamp,
    {ok, State#state{ last_batch_timelag = LastBatchTimelag }}.

aggregate_element(State = #state{ last_batch_timelag = LastBatchTimelag }) ->
    {ok, LastBatchTimelag, State}.

handle_periodic_aggregate(Aggregate) ->
    io:format("aggregate: ~p\n", [Aggregate]).

