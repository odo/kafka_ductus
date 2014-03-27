-module(ductus_redis).
-export([start_link/3]).

start_link(Name, Host, Port) ->
    {ok, Client} = eredis:start_link(Host, Port),
    register(Name, Client),
    {ok, Client}.
