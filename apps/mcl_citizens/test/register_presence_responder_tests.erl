%%% @doc register_presence: who may register, what is stored, what is replied,
%%% and the fact that federates it.
%%%
%%% THE CITIZEN IS THE CALLER. macula 12 signs every CALL end to end with the
%%% caller's identity key, verifies it at this provider, and puts that key's
%%% node id in the payload as `caller', overwriting anything the payload sent
%%% under that key. So the registration is the caller's own, with no proof in
%%% the payload. A `citizen_did' the caller sends anyway must name itself.
%%%
%%% Nothing here boots mcl_om, so the federation publish finds no mesh
%%% (`mcl_om:mesh_handles/0' answers `mesh_unavailable') and is skipped; every
%%% registration below asserts that this does not cost the reply.
-module(register_presence_responder_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MINUTE, 60_000).

registrations_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun registers_the_caller/1,
      fun accepts_a_citizen_did_that_names_the_caller/1,
      fun refuses_a_citizen_did_that_is_not_the_caller/1,
      fun refuses_a_call_without_a_caller/1,
      fun stamps_registered_at_from_this_clock/1,
      fun caps_a_ttl_above_twenty_minutes/1,
      fun refuses_a_ttl_that_is_not_a_positive_integer/1,
      fun a_registration_replaces_the_callers_entry/1]}.

%% The realm name is set, as the running node has it: an unset one stops the
%% node at boot, so it is not a state a call can meet.
setup() ->
    _ = application:load(mcl_citizens),
    ok = application:set_env(mcl_citizens, realm_name, "io.macula"),
    {ok, Pid} = citizen_directory:start_link(),
    unlink(Pid),
    Pid.

teardown(Pid) ->
    application:unset_env(mcl_citizens, realm_name),
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.

registers_the_caller(_) ->
    Caller = did(),
    Reply = register(payload(Caller)),
    {ok, Entry} = citizen_directory:find(Caller),
    [?_assertMatch(#{ok := 1, expires_at := _}, Reply),
     ?_assertEqual(<<"agent">>, maps:get(citizen_kind, Entry)),
     ?_assertEqual(<<"metis">>, maps:get(display_name, Entry)),
     ?_assertEqual([<<"conversation">>], maps:get(offers, Entry))].

accepts_a_citizen_did_that_names_the_caller(_) ->
    Caller = did(),
    Payload = (payload(Caller))#{citizen_did => {text, binary:encode_hex(Caller, lowercase)}},
    [?_assertMatch(#{ok := 1}, register(Payload)),
     ?_assertMatch({ok, _}, citizen_directory:find(Caller))].

%% Registering someone else is the squatting the old in-payload proof existed
%% to stop. The caller is verified, so naming another DID is simply refused.
refuses_a_citizen_did_that_is_not_the_caller(_) ->
    Caller = did(),
    Other = did(),
    Payload = (payload(Caller))#{citizen_did => {text, binary:encode_hex(Other, lowercase)}},
    [?_assertEqual(#{ok => 0, error => {text, <<"citizen_did_is_not_the_caller">>}},
                   register(Payload)),
     ?_assertEqual({error, not_found}, citizen_directory:find(Other)),
     ?_assertEqual({error, not_found}, citizen_directory:find(Caller))].

refuses_a_call_without_a_caller(_) ->
    Caller = did(),
    [?_assertEqual(#{ok => 0, error => {text, <<"no_verified_caller">>}},
                   register(maps:remove(caller, payload(Caller))))].

stamps_registered_at_from_this_clock(_) ->
    Caller = did(),
    Before = now_ms(),
    #{ok := 1, expires_at := ExpiresAt} = register(payload(Caller)),
    After = now_ms(),
    {ok, #{registered_at := RegisteredAt} = Entry} = citizen_directory:find(Caller),
    [?_assert(Before =< RegisteredAt andalso RegisteredAt =< After),
     ?_assertEqual(RegisteredAt + 20 * ?MINUTE, ExpiresAt),
     ?_assertEqual(ExpiresAt, maps:get(expires_at, Entry))].

caps_a_ttl_above_twenty_minutes(_) ->
    Caller = did(),
    #{ok := 1, expires_at := ExpiresAt} =
        register((payload(Caller))#{ttl_ms => 30 * 24 * 60 * ?MINUTE}),
    {ok, #{registered_at := RegisteredAt}} = citizen_directory:find(Caller),
    [?_assertEqual(RegisteredAt + 20 * ?MINUTE, ExpiresAt)].

refuses_a_ttl_that_is_not_a_positive_integer(_) ->
    Outcomes = [begin
                    Caller = did(),
                    {register((payload(Caller))#{ttl_ms => TtlMs}), citizen_directory:find(Caller)}
                end || TtlMs <- [0, -5, 1.5, {text, <<"soon">>}]],
    [?_assertEqual({#{ok => 0, error => {text, <<"invalid_ttl_ms">>}}, {error, not_found}}, O)
     || O <- Outcomes].

a_registration_replaces_the_callers_entry(_) ->
    Caller = did(),
    #{ok := 1} = register(payload(Caller)),
    #{ok := 1} = register(maps:remove(display_name, payload(Caller))),
    {ok, Entry} = citizen_directory:find(Caller),
    [?_assertNot(maps:is_key(display_name, Entry))].

%% macula merges `caller' only into a map payload, so a null or a list arrives
%% bare. Refused as the caller's mistake, not crashed into a retryable
%% temporary_relay_failure.
refuses_a_payload_that_is_not_a_map_test() ->
    [?assertEqual({reply, #{ok => 0, error => {text, <<"invalid_payload">>}}, []},
                  register_presence_responder:handle_request(P, []))
     || P <- [null, [], {text, <<"hello">>}, 42]].

%%------------------------------------------------------------------------------
%% The federated fact, pure
%%------------------------------------------------------------------------------

%% registered_at and ttl_ms are what a receiving instance computes its own
%% expiry from; expires_at stays for subscribers that show it.
presence_fact_sends_text_as_text_and_the_did_as_hex_test() ->
    Did = did(),
    Fields = #{citizen_did => Did, citizen_kind => <<"agent">>, display_name => <<"metis">>,
               offers => [<<"conversation">>], registered_at => 1, ttl_ms => 2, expires_at => 3},
    ?assertEqual(#{citizen_did => {text, binary:encode_hex(Did, lowercase)},
                   citizen_kind => {text, <<"agent">>},
                   display_name => {text, <<"metis">>},
                   offers => [{text, <<"conversation">>}],
                   registered_at => 1, ttl_ms => 2, expires_at => 3},
                 register_presence_responder:presence_fact(Fields)).

%%------------------------------------------------------------------------------

register(Payload) ->
    {reply, Reply, []} = register_presence_responder:handle_request(Payload, []),
    Reply.

%% A register_presence payload as it reaches the handler: text arrives
%% `{text, Bin}'-tagged and macula has put the verified caller in.
payload(Caller) ->
    #{citizen_kind => {text, <<"agent">>},
      display_name => {text, <<"metis">>},
      offers => [{text, <<"conversation">>}],
      caller => Caller}.

did() -> crypto:strong_rand_bytes(32).

now_ms() -> erlang:system_time(millisecond).
