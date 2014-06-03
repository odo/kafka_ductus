-module(ductus_adapter).

-behaviour(gen_server).
-export([start_link/4, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, status/1, aggregate_element/1]).

-record(state, { topic, consumer, calls, report, callback_module, callback_state, buffer }).

%% Public API

start_link(SourceHost, SourcePort, Topic, CallbackModule) ->
    gen_server:start_link(?MODULE, [SourceHost, SourcePort, Topic, CallbackModule], []).

status(Server) ->
    gen_server:call(Server, status).

aggregate_element(Server) ->
    gen_server:call(Server, aggregate_element).

%% Callbacks

init([ConsumerHost, ConsumerPort, {Topic, CallbackData}, CallbackModule]) ->

    % we are not opening the connections right here
    % so if there is a problem the supervisor will retry
    self() ! {init, {ConsumerHost, ConsumerPort, {Topic, CallbackData}, CallbackModule}},

    {ok, undefined}.

handle_call(status, _From, State =
    #state{ topic = Topic, consumer = Consumer }) ->

    {reply, offset_diff_and_status_line(Topic, Consumer), State};

handle_call(aggregate_element, _From, State =
    #state{ topic = Topic, callback_module = CallbackModule, callback_state = CallbackState }) ->

    {ok, Reply, CallbackStateNew} = CallbackModule:aggregate_element(CallbackState),
    {reply, {Topic, Reply}, State#state{ callback_state = CallbackStateNew }}.

handle_cast(Msg, State) ->
    throw({cant_handle, Msg}),
    {noreply, State}.

handle_info({init, {ConsumerHost, ConsumerPort, {TopicString, CallbackData}, CallbackModule}}, undefined) ->
    Report = erlconf:get_value(ductus, report),

    Topic          = list_to_binary(TopicString),
    Offset         = ductus_offsets:offset(Topic),
    {ok, Consumer} = kafka_consumer:start_link(ConsumerHost, ConsumerPort, Topic, 0, 0, fun noop/3, 10000),
    ok             = kafka_consumer:set_offset(Consumer, Offset),

    {ok, CallbackState}  = CallbackModule:init(Topic, CallbackData),

    lager:info("Starting kafka_ductus from ~p \t using ~p \t at offset ~p .", [Topic, CallbackModule, Offset]),
    % enter the loop
    self() ! adapt,

    State = #state{ topic = Topic, consumer = Consumer, calls = 1, report = Report,
        callback_module = CallbackModule, callback_state = CallbackState },
    {noreply, State};

handle_info(adapt, State = #state{
    consumer        = Consumer,      topic  = Topic, calls = Calls,
    callback_state  = CallbackState, buffer = Buffer,
    callback_module = CallbackModule  }) ->

    {Offset, Messages}                   = fetch(Buffer, Consumer),
    {CallbackStateNew, NewBuffer, Delay} = call_back(Messages, Offset, CallbackState, Topic, CallbackModule),
    maybe_report_lag(State),

    loop(Messages, Delay),

    {noreply, State#state{ calls = Calls + 1, callback_state = CallbackStateNew, buffer = NewBuffer }}.

fetch(undefined, Consumer) ->
    {ok, OffsetAndMsgs} = kafka_consumer:fetch_with_offset(Consumer),
    OffsetAndMsgs;
fetch(Buffer, _) ->
    Buffer.

call_back(Messages, Offset, CallbackState, Topic, CallbackModule)->
    case CallbackModule:handle_messages(Messages, Offset, CallbackState) of
        {ok, CallbackStateReply} ->
            % the messages are consumed by the handler,
            % we persist the offset
            ductus_offsets:set_offset(Topic, Offset),
            {CallbackStateReply, undefined, undefined};
        {defer, Delay, CallbackStateReply} ->
            {CallbackStateReply, {Offset, Messages}, Delay}
    end.

loop([], _) ->
    erlang:send_after(500, self(), adapt);
loop(_, undefined) ->
    self() ! adapt;
loop(_, Delay) ->
    erlang:send_after(Delay, self(), adapt).

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

maybe_report_lag(#state{ report = false }) ->
    noop;
maybe_report_lag(#state{ topic = Topic, consumer = Consumer, calls = Calls }) ->
    case Calls rem 5 of
        0 -> report_lag(Topic, Consumer);
        _ -> noop
    end.

report_lag(Topic, Consumer) ->
    lager:info(status_line(Topic, Consumer), []).

status_line(Topic, Consumer) ->
    {_, StatusLine} = offset_diff_and_status_line(Topic, Consumer),
    StatusLine.

offset_diff_and_status_line(Topic, Consumer) ->
    {ok, CurrentOffset} = kafka_consumer:get_current_offset(Consumer),
    OffsetDiff  = ductus_offsets:offset_from_kafka(Topic, Consumer, newest) - CurrentOffset,
    Lag         = round(OffsetDiff / (1024.0 * 1024.0)),
    OffsetStr   = integer_to_list(CurrentOffset),
    LagStr      = integer_to_list(Lag),
    TopicStrEq  = string:left(binary_to_list(Topic), 10, 32),
    LagStrEq    = string:right(LagStr,    10, 32),
    OffsetStrEq = string:right(OffsetStr, 20, 32),
    StatusLine = TopicStrEq ++ ": " ++ OffsetStrEq ++ " Offset" ++ LagStrEq ++ " MB lag\n",
    {OffsetDiff, StatusLine}.

noop(_, _, _) -> noop.

