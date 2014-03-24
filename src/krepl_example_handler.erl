-module(krepl_example_handler).

-behaviour(krepl_callback).

-export([init/2, handle_messages/3, aggregate_element/1, handle_periodic_aggregate/1]).

-record(state, { topic, last_message_count }).


init(Topic, InitData) ->
    io:format("init: ~p\n", [{Topic, InitData}]),
    {ok, #state{ topic = Topic }}.

handle_messages(Msgs, Offset, State) ->
    MessageCount = length(Msgs),
    io:format("handle with msg: ~p offset: ~p state: ~p\n", [MessageCount, Offset, State]),
    {ok, State#state{ last_message_count = MessageCount }}.

aggregate_element(State = #state{ last_message_count = MessageCount }) ->
    {ok, MessageCount, State}.

handle_periodic_aggregate(Aggregate) ->
    io:format("aggregate: ~p\n", [Aggregate]).

