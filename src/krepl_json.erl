% Dealing with jiffy
%
-module (krepl_json).
-compile ([export_all]).

% Insert a new element to the JSON-object.
store(Json, Key, Value) ->
    % Note that orddict:store inserts elements sorted, which orddict:fetch
    % assumes to be true to operate.
    orddict:store(Key, Value, Json).

% Create a new JSON-struct in the underlying representation.
create() ->
    % For orddict, this would be the empty list: [].
    orddict:new().

% Construct a new JSON struct from the given proplist.
% By calling `store`, of the underlying representation, recursively for every
% element passed in, the resulting structure will be adhere to the rules of its
% representation. In the case of orddicts, this is order of its keys.
construct(Proplist = [{_,_}|_]) ->
    Step = fun({Key, Value}, Json) ->
        store(Json, Key, construct(Value))
    end,
    lists:foldl(Step, create(), Proplist);

% For all other elements which are not proplists, return their identity; only
% proplists need recursive folding to ensure order in the underlying orddict.
construct(Literal) -> Literal.

% Decode a JSON binary to a JSON struct or literal.
decode(Binary) ->
    construct(unpack(jiffy:decode(Binary))).


% JSON is encoded from and decoded to recursive JSON-structures as used by
% jiffy, see https://github.com/davisp/jiffy for more information.
% Thus any structure obtained via jiffy:decode needs to be unpacked first.
% That is stripped of extra tuples and list constructors.

% Attempts to extract a orddict from the given jiffy-JSON.
unpack(Json) when is_list(Json) orelse is_tuple(Json) ->
    unpack(Json, orddict:new());

%% Only tuples and list require deeper unpacking, return simple structs.
unpack(Json) -> Json.

% Recursively unpacks a nested jiffy-JSON object.
unpack({Proplist}, Dict) when is_list(Proplist) ->
    lists:foldl(
        fun({Key, Value}, Acc) ->
            orddict:store(Key, unpack(Value), Acc)
        end,
        Dict,
        Proplist);

% List of jiffy-JSON => list of unpacked structs.
unpack(List, _) when is_list(List) ->
  [unpack(Elem) || Elem <- List].

