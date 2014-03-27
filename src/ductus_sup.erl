-module(ductus_sup).

-behaviour(supervisor2).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor2:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    RedisHost      = erlconf:get_value(ductus, redis_host),
    RedisPort      = erlconf:get_value(ductus, redis_port),
    PeriodicPeriod = erlconf:get_value(ductus, periodic_period),
    CallbackModule = erlconf:get_value(ductus, callback_module),

    Redis      = {ductus_redis,
        {ductus_redis, start_link, [ductus_redis, RedisHost, RedisPort]},
        {permanent, 10}, 5000, worker, [ductus_redis, eredis, eredis_client]},
    AdapterSup = {ductus_adapter_sup,
        {ductus_adapter_sup, start_link, []},
        {permanent, 10}, 5000, supervisor, [ductus_apapter_sup]},
    RestartStrategy = {one_for_all, 100, 10},
    Children =
    case PeriodicPeriod of
        undefined ->
            [Redis, AdapterSup];
        Period ->
            Periodic = {ductus_periodic,
            {ductus_periodic, start_link, [Period, CallbackModule]},
            {permanent, 10}, 5000, worker, [ductus_periodic]},
            [Redis, AdapterSup, Periodic]
    end,
    {ok, { RestartStrategy, Children} }.
