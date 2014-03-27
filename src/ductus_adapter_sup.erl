-module(ductus_adapter_sup).

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
    SourceHost             = erlconf:get_value(ductus, source_host),
    SourcePort             = erlconf:get_value(ductus, source_port),
    CallbackModule         = erlconf:get_value(ductus, callback_module),
    TopicsAndCallbackDatas = erlconf:get_value(ductus, topics),
    Adapter = fun({Topic, CallbackData}) ->
        {process_name(Topic),
         {ductus_adapter, start_link, [SourceHost, SourcePort, {Topic, CallbackData}, CallbackModule]},
        permanent, brutal_kill, worker, [ductus_adapter]}
    end,
    Children = [Adapter(T) || T <- TopicsAndCallbackDatas],
    RestartStrategy = {one_for_one, 100, 10},
    {ok, { RestartStrategy, Children} }.

process_name(Topic) ->
    list_to_atom("ductus_adapter_" ++ Topic).

