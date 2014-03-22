-module(krepl_example_handler).

-behaviour(krepl_callback).

-export([init/2, handle/3]).

init(Topic, InitData) ->
    io:format("init: ~p\n", [{Topic, InitData}]),
    {ok, {Topic, InitData}}.

handle(Msgs, Offset, State) ->
    io:format("handle with msg: ~p offset: ~p state: ~p\n", [length(Msgs), Offset, State]),
    {ok, State}.
