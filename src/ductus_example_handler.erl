-module(ductus_example_handler).

-behaviour(ductus_callback).

-export([init/2, handle_messages/3, aggregate_element/1, handle_periodic_aggregate/1]).

-define(SECONDS1970, calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}})).

-record(state, { topic, last_batch_timelag }).

%% callback

init(Topic, _InitData) ->
    ductus_librato:init(),
    {ok, #state{ topic = Topic, last_batch_timelag = -1 }}.

handle_messages([], _Offset, State) ->
    {ok, State#state{ last_batch_timelag = 0}};

handle_messages(Msgs, _Offset, State) ->
    LastBatchTimelag = batch_timelag(Msgs),
    {ok, State#state{ last_batch_timelag = LastBatchTimelag }}.

aggregate_element(State = #state{ last_batch_timelag = LastBatchTimelag }) ->
    {ok, LastBatchTimelag, State}.

handle_periodic_aggregate(Gauges) ->
    Metric = list_to_binary(ductus:handler_name() ++ ".seconds_lag"),
    ductus_librato:gauges("me@home", "your_api_key_here", Metric, Gauges).

%% internal

batch_timelag(Msgs) ->
    FirstMessage   = hd(Msgs),
    [_, TSBin | _] = binary:split(binary_part(FirstMessage, {0, min(byte_size(FirstMessage), 100)}), <<" ">>, [global]),
    Timestamp      = list_to_integer(binary_to_list(TSBin)),
    Datetime       = calendar:now_to_universal_time(os:timestamp()),
    SecondsNow     = calendar:datetime_to_gregorian_seconds(Datetime) - ?SECONDS1970,
    SecondsNow - Timestamp.
