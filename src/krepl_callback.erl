-module(krepl_callback).

-callback init(Topic :: list(), InitData :: term()) ->
    tuple('ok', State :: term()) | tuple('error', Reason :: term()).

-callback handle_messages(Massages :: list(binary()), Offset :: integer(), State :: term()) ->
    tuple('ok', State :: term()) | tuple('error', Reason :: term()).

-callback aggregate_element(State :: term()) ->
    tuple('ok', Reply :: term(), State :: term()) | tuple('error', Reason :: term()).

-callback handle_periodic_aggregate(Aggregate :: tuple()) ->
    'ok' | tuple('error', Reason :: term()).








