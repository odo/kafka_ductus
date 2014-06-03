-module(ductus_adapter_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-record(state, { topic, consumer, calls, report, callback_module, callback_state, buffer }).

ductu_adapter_test_() ->
    [{foreach, local,
      fun test_setup/0,
      fun test_teardown/1,
      [
        fun test_init/0,
        fun test_callback_consumption/0,
        fun test_callback_defer/0,
        fun test_callback_with_buffer_consumption/0,
        fun test_callback_with_buffe_defer/0
      ]}
    ].

test_setup() ->
    application:start(sasl),

    % config
    meck:new(erlconf),
    meck:expect(erlconf, get_value,
        fun(ductus, report) -> false
    end),

    % offsets
    meck:new(ductus_offsets),
    meck:expect(ductus_offsets, offset, fun(_) -> 42 end),

    % consumer
    meck:new(kafka_consumer),
    meck:expect(kafka_consumer, start_link, fun(_, _, _, _, _, _, _) ->
        {ok, consumer}
    end),
    meck:expect(kafka_consumer, set_offset, fun(_, _) -> ok end),

    % callback
    meck:new(test_callback, [non_strict]).

test_teardown(_) ->
    meck:unload(erlconf),
    meck:unload(ductus_offsets),
    meck:unload(kafka_consumer),
    meck:unload(test_callback).

test_init() ->
    % the first call just passes a message
    % with all relevant arguments to itself
    InitReply = ductus_adapter:init(
        [host, port, {"topic", callback}, test_callback]
    ),
    ?assertEqual({ok, undefined}, InitReply),
    Msg = {init, {host, port, {"topic", callback}, test_callback}},
    assert_msg(Msg),

    % that message then is handled by initating the
    % callback module and the consumer
    meck:expect(test_callback, init,
        fun(<<"topic">>, callback) -> {ok, callback_state}
    end),
    InitCallReply = ductus_adapter:handle_info(Msg, undefined),
    ?assertEqual({noreply, init_state()} , InitCallReply),
    assert_msg(adapt).

test_callback_consumption() ->
    % new messages are fetched
    % and delivered, only incrementing the counter
    meck:expect(kafka_consumer, fetch_with_offset,
        fun(consumer) -> {ok, {53, [1, 2 ,3]}} end),
    meck:expect(test_callback, handle_messages,
        fun([1, 2, 3], 53, callback_state) -> {ok, callback_state2}
    end),
    meck:expect(ductus_offsets, set_offset,
        fun(<<"topic">>, 53) -> undefined end),
    InitState         = init_state(),
    {noreply, State2} = ductus_adapter:handle_info(adapt, InitState),
    assert_msg(adapt),
    StateExpect = InitState#state{ calls = 2, callback_state = callback_state2},
    ?assertEqual(StateExpect, State2).

test_callback_defer() ->
    % new messages are fetched, consumption is defered,
    % messages and offset kept in the buffer and no offset
    % is persisted
    meck:expect(kafka_consumer, fetch_with_offset,
        fun(consumer) -> {ok, {53, [1, 2 ,3]}} end),
    meck:expect(test_callback, handle_messages,
        fun([1, 2, 3], 53, callback_state) -> {defer, 0, callback_state2}
    end),
    InitState         = init_state(),
    {noreply, State2} = ductus_adapter:handle_info(adapt, InitState),
    assert_msg(adapt),
    StateExpect = InitState#state{ calls = 2, buffer = {53, [1, 2, 3]}, callback_state = callback_state2},
    ?assertEqual(StateExpect, State2).

test_callback_with_buffer_consumption() ->
    % no new massages are fetched since the buffer is no empty,
    % after delivery, buffers are empty
    meck:expect(test_callback, handle_messages,
        fun([4, 5, 6], 666, callback_state) -> {ok, callback_state2}
    end),
    meck:expect(ductus_offsets, set_offset,
        fun(<<"topic">>, 666) -> undefined end),
    InitState         = init_state(),
    StateWithBuffer   = InitState#state{ buffer = {666, [4, 5, 6]} },
    {noreply, State2} = ductus_adapter:handle_info(adapt, StateWithBuffer),
    assert_msg(adapt),
    StateExpect = InitState#state{ calls = 2, callback_state = callback_state2},
    ?assertEqual(StateExpect, State2).

test_callback_with_buffe_defer() ->
    % no new massages are fetched since the buffer is no empty,
    % after defer, buffers are the same and no offset is persisted
    meck:expect(test_callback, handle_messages,
        fun([4, 5, 6], 666, callback_state) -> {defer, 0, callback_state2}
    end),
    InitState         = init_state(),
    StateWithBuffer   = InitState#state{ buffer = {666, [4, 5, 6]} },
    {noreply, State2} = ductus_adapter:handle_info(adapt, StateWithBuffer),
    assert_msg(adapt),
    StateExpect = StateWithBuffer#state{ calls = 2, callback_state = callback_state2},
    ?assertEqual(StateExpect, State2).

init_state() ->
    #state{
        topic = <<"topic">>, consumer = consumer,
        calls = 1, report = false, callback_module = test_callback,
        callback_state = callback_state, buffer = undefined
    }.

assert_msg(Msg) ->
    Reply =
    receive
        Re  -> Re
    after
        100 -> timeout
    end,
    ?assertEqual(Msg, Reply).

-endif.
