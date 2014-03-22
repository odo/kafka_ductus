-module(krepl_sup).

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
    RedisHost = erlconf:get_value(krepl, redis_host),
    RedisPort = erlconf:get_value(krepl, redis_port),

    Redis      = {krepl_redis,
        {krepl_redis, start_link, [krepl_redis, RedisHost, RedisPort]},
        {permanent, 10}, 5000, worker, [krepl_redis, eredis, eredis_client]},
    AdapterSup = {krepl_adapter_sup,
        {krepl_adapter_sup, start_link, []},
        {permanent, 10}, 5000, supervisor, [krepl_apapter_sup]},
    RestartStrategy = {one_for_all, 100, 10},
    {ok, { RestartStrategy, [Redis, AdapterSup]} }.
