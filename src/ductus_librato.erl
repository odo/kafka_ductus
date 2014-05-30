-module(ductus_librato).
-export([init/0, gauges/4]).

init() ->
    application:start(inets),
    application:start(crypto),
    application:start(public_key),
    application:start(ssl).

gauges(Email, Token, Metric, Gauges) when is_list(Metric) ->
    gauges(Email, Token, list_to_binary(Metric), Gauges);

gauges(Email, Token, Metric, Gauges) ->
    Url        = "https://metrics-api.librato.com/v1/metrics",
    AuthString = binary_to_list(base64:encode(Email ++ ":" ++ Token)),
    GaugesDict = [{[{name, Metric}, {value, Value}, {source, Source}]} || {Source, Value} <- Gauges],
    Body       = jiffy:encode({[{gauges, GaugesDict}]}),
    httpc:request(post, {Url, [{"Authorization", "Basic " ++ AuthString}], "application/json", Body}, [], []).

