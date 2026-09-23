%%% @doc get_citizen and list_citizens replies, against a running directory.
-module(lookup_responders_tests).

-include_lib("eunit/include/eunit.hrl").

get_citizen_refuses_a_payload_that_is_not_a_map_test() ->
    [?assertEqual({reply, #{ok => 0, error => {text, <<"invalid_payload">>}}, []},
                  get_citizen_responder:handle_request(P, []))
     || P <- [null, [], {text, <<"x">>}]].

lookups_test_() ->
    {setup,
     fun() -> {ok, Pid} = citizen_directory:start_link(), unlink(Pid), Pid end,
     fun(Pid) -> Ref = monitor(process, Pid), exit(Pid, shutdown),
                 receive {'DOWN', Ref, process, Pid, _} -> ok end end,
     fun replies/1}.

replies(_) ->
    Did = crypto:strong_rand_bytes(32),
    Hex = binary:encode_hex(Did, lowercase),
    Now = erlang:system_time(millisecond),
    admitted = citizen_directory:admit(#{citizen_did => Did, citizen_kind => <<"agent">>,
                                         display_name => <<"metis">>, offers => [],
                                         registered_at => Now, expires_at => Now + 60_000},
                                       fun(_, _) -> admit end),
    Unknown = binary:encode_hex(crypto:strong_rand_bytes(32), lowercase),
    {reply, Found, []} = get_citizen_responder:handle_request(#{citizen_did => {text, Hex}}, []),
    {reply, Missing, []} = get_citizen_responder:handle_request(#{citizen_did => {text, Unknown}}, []),
    {reply, Garbage, []} = get_citizen_responder:handle_request(#{citizen_did => {text, <<"x">>}}, []),
    {reply, Listed, []} = list_citizens_responder:handle_request(#{}, []),
    [?_assertMatch(#{ok := 1, citizen := #{citizen_did := {text, Hex},
                                           display_name := {text, <<"metis">>}}}, Found),
     ?_assertEqual(#{ok => 0, error => {text, <<"not_found">>}}, Missing),
     ?_assertEqual(#{ok => 0, error => {text, <<"invalid_citizen_did">>}}, Garbage),
     ?_assertMatch(#{ok := 1, citizens := [#{citizen_did := {text, Hex}}]}, Listed)].
