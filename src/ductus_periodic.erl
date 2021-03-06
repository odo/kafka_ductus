-module(ductus_periodic).

-behaviour(gen_server).
-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, request_aggregate_element/3]).

%% Public API

start_link(Period, CallbackModule) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Period, CallbackModule}, []).

%% Callbacks

init({Period, CallbackModule}) ->
    self() ! act,
    {ok, {Period, CallbackModule}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(act, {Period, CallbackModule}) ->
    Before     = os:timestamp(),
    act(CallbackModule),
    Elapsed = round(timer:now_diff(os:timestamp(), Before) / 1000),
    Delay   = max(0, Period - Elapsed),
    erlang:send_after(Delay, self(), act),
    {noreply, {Period, CallbackModule}};

% this is probably a late reply from one of the adapters
handle_info({Ref, _}, State) when is_reference(Ref) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

act(CallbackModule) ->
    AggregateElements =
    case whereis(ductus_adapter_sup) of
        undefined ->
            [];
        _ ->
            Pids = [Pid || {_, Pid, _, _} <- supervisor:which_children(ductus_adapter_sup), is_pid(Pid)],
            [E || E <- collect_elements(Pids), E =/= timeout]
    end,
    CallbackModule:handle_periodic_aggregate(orddict:from_list(AggregateElements)).

collect_elements(Pids) ->
    Ref = make_ref(),
    [spawn(?MODULE, request_aggregate_element, [self(), Ref, Pid]) || Pid <- Pids],
    [collect_aggregate_elements(Ref) || _ <- Pids].

request_aggregate_element(From, Ref, Pid) ->
    Status = ductus_adapter:aggregate_element(Pid),
    From ! {Ref, Status}.

collect_aggregate_elements(Ref) ->
    receive
        {Ref, Status} -> Status
    after 500 ->
        timeout
    end.
