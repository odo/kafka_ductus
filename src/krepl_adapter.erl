-module(krepl_adapter).

-behaviour(gen_server).
-export([start_link/4, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, status/1, aggregate_element/1]).

-record(state, { consume_topic, consumer, calls, report, callback_module, callback_state }).

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
    #state{ consume_topic = ConsumerTopic, consumer = Consumer }) ->

    {reply, offset_diff_and_status_line(ConsumerTopic, Consumer), State};

handle_call(aggregate_element, _From, State =
    #state{ consume_topic = ConsumerTopic, callback_module = CallbackModule, callback_state = CallbackState }) ->

    {ok, Reply, CallbackStateNew} = CallbackModule:aggregate_element(CallbackState),
    {reply, {ConsumerTopic, Reply}, State#state{ callback_state = CallbackStateNew }}.

handle_cast(Msg, State) ->
    throw({cant_handle, Msg}),
    {noreply, State}.

handle_info({init, {ConsumerHost, ConsumerPort, {ConsumerTopicString, CallbackData}, CallbackModule}}, undefined) ->
    Report = erlconf:get_value(krepl, report),

    ConsumerTopic = list_to_binary(ConsumerTopicString),
    {ok, Consumer} = kafka_consumer:start_link(ConsumerHost, ConsumerPort, ConsumerTopic, 0, 0, fun noop/3, 10000),
    Offset         = krepl_offsets:offset(ConsumerTopic),
    ok             = kafka_consumer:set_offset(Consumer, Offset),

    {ok, CallbackState}  = CallbackModule:init(ConsumerTopic, CallbackData),

    lager:info("Starting replication from ~p \t using ~p \t at offset ~p .", [ConsumerTopic, CallbackModule, Offset]),
    % enter the loop
    self() ! adapt,

    State = #state{ consume_topic = ConsumerTopic, consumer = Consumer, calls = 1, report = Report,
        callback_module = CallbackModule, callback_state = CallbackState },
    {noreply, State};

handle_info(adapt, State =
    #state{ consumer = Consumer, consume_topic = ConsumerTopic, calls = Calls,
        callback_module = CallbackModule, callback_state = CallbackState }) ->

    CallbackStateNew =
    case kafka_consumer:fetch_with_offset(Consumer) of
        {ok, {_, []}} ->
            erlang:send_after(500, self(), adapt),
            CallbackState;
        {ok, {ConsumerOffset, Msgs}} ->

            {ok, CallbackStateReply} = CallbackModule:handle(Msgs, ConsumerOffset, CallbackState),

            %{ok, _ProducerOffset} = kafka_producer:produce_ack(ProducerTopic, 0, Msgs, Producer),
            krepl_offsets:set_offset(ConsumerTopic, ConsumerOffset),
            self() ! adapt,
            CallbackStateReply
    end,
    maybe_report_lag(State),
    {noreply, State#state{ calls = Calls + 1, callback_state = CallbackStateNew }}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

maybe_report_lag(#state{ report = false }) ->
    noop;
maybe_report_lag(#state{ consume_topic = ConsumerTopic, consumer = Consumer, calls = Calls }) ->
    case Calls rem 5 of
        0 -> report_lag(ConsumerTopic, Consumer);
        _ -> noop
    end.

report_lag(ConsumerTopic, Consumer) ->
    lager:info(status_line(ConsumerTopic, Consumer), []).

status_line(ConsumerTopic, Consumer) ->
    {_, StatusLine} = offset_diff_and_status_line(ConsumerTopic, Consumer),
    StatusLine.

offset_diff_and_status_line(ConsumerTopic, Consumer) ->
    {ok, CurrentOffset} = kafka_consumer:get_current_offset(Consumer),
    OffsetDiff  = krepl_offsets:offset_from_kafka(ConsumerTopic, Consumer, newest) - CurrentOffset,
    Lag         = round(OffsetDiff / (1024.0 * 1024.0)),
    OffsetStr   = integer_to_list(CurrentOffset),
    LagStr      = integer_to_list(Lag),
    ConsumerTopicStrEq  = string:left(binary_to_list(ConsumerTopic), 10, 32),
    LagStrEq    = string:right(LagStr,    10, 32),
    OffsetStrEq = string:right(OffsetStr, 20, 32),
    StatusLine = ConsumerTopicStrEq ++ "->    " ++ OffsetStrEq ++ " Offset" ++ LagStrEq ++ " MB lag\n",
    {OffsetDiff, StatusLine}.

noop(_, _, _) -> noop.

