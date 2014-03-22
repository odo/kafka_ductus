-module(krepl_adapter_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    SourceHost             = erlconf:get_value(krepl, source_host),
    SourcePort             = erlconf:get_value(krepl, source_port),
    CallbackModule         = erlconf:get_value(krepl, callback_module),
    TopicsAndCallbackDatas = erlconf:get_value(krepl, topics),
    Adapter = fun({Topic, CallbackData}) ->
        {process_name(Topic),
         {krepl_adapter, start_link, [SourceHost, SourcePort, {Topic, CallbackData}, CallbackModule]},
        permanent, brutal_kill, worker, [krepl_adapter]}
    end,
    Children = [Adapter(T) || T <- TopicsAndCallbackDatas],
    RestartStrategy = {one_for_one, 100, 10},
    {ok, { RestartStrategy, Children} }.

process_name(Topic) ->
    list_to_atom("krepl_adapter_" ++ Topic).

