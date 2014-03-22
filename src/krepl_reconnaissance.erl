-module(krepl_reconnaissance).

-compile(export_all).

other_nodes_with_same_config() ->
    Others     = reconnaissance:discover(),
    Profile    = profile(),
    Intersect = fun({IP, HandlerName, OtherProfile}) ->
        {IP, HandlerName, sets:intersection(OtherProfile, Profile)}
    end,
    Intersections = lists:map(Intersect, Others),
    Filter = fun({_, _, Intersection}) -> sets:size(Intersection) > 0 end,
    lists:filter(Filter, Intersections).

request() ->
    <<"krepl profile, please.">>.

response(IP, _Port, <<"krepl profile, please.">>) ->
    term_to_binary({IP, krepl:handler_name(), profile()}).

% the profile is the list of all sources and targets
% spelled out both ways so we can detect with a basic
% intersetction if another node is replications in the
% same or the opposite direction
profile() ->
    SourceHost = erlconf:get_value(krepl, source_host),
    SourcePort = erlconf:get_value(krepl, source_port),
    TargetHost = erlconf:get_value(krepl, target_host),
    TargetPort = erlconf:get_value(krepl, target_port),
    Topics     = erlconf:get_value(krepl, topics),
    ReplicationPairs =
        [replication_pairs(SourceHost, SourcePort, TargetHost, TargetPort, Topic) || Topic <- Topics],
    sets:from_list(lists:flatten(ReplicationPairs)).

replication_pairs(SH, SP, TH, TP, Topic) when is_list(Topic) ->
    replication_pairs(SH, SP, TH, TP, {Topic, Topic});
replication_pairs(SH, SP, TH, TP, {ST, TT}) ->
    [{{SH, SP, ST}, {TH, TP, TT}}, {{TH, TP, TT}, {SH, SP, ST}}].

handle_response(_IP, _Port, Response) ->
    binary_to_term(Response).
