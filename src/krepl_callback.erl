-module(krepl_callback).

-callback init(Topic :: list(), InitData :: term()) ->
    tuple('ok', State :: term()) | tuple('error', Reason :: term()).

-callback handle(Massages :: list(binary()), Offset :: integer(), State :: term()) ->
    tuple('ok', State :: term()) | tuple('error', Reason :: term()).


