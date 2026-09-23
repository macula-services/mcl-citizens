%%% @doc The federation half: which presence facts are heard, and what is
%%% stored from them.
%%%
%%% The topic is open to anyone in the realm, so a fact counts only when
%%% macula verified its publisher signature AND the publisher is one of the
%%% mcl-citizens instances configured. What is stored expires by this
%%% instance's own arithmetic over the fact's registered_at and ttl_ms, never
%%% at the fact's own expires_at, and the latest registration wins.
-module(hear_citizen_presence_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LISTED, <<1:256>>).
-define(UNLISTED, <<2:256>>).
-define(MINUTE, 60_000).
-define(MONTH, 30 * 24 * 60 * ?MINUTE).

hearing_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun admits_a_verified_fact_from_a_listed_instance/1,
      fun drops_a_fact_from_an_instance_not_listed/1,
      fun drops_a_fact_whose_signature_did_not_verify/1,
      fun stores_its_own_expiry_not_the_facts/1,
      fun caps_a_ttl_above_twenty_minutes/1,
      fun refuses_a_fact_without_registered_at/1,
      fun refuses_a_registration_more_than_a_minute_ahead/1,
      fun a_replayed_earlier_registration_replaces_nothing/1,
      fun drops_a_fact_whose_did_is_not_a_did/1]}.

setup() ->
    {ok, Pid} = citizen_directory:start_link(),
    unlink(Pid),
    Pid.

teardown(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.

admits_a_verified_fact_from_a_listed_instance(_) ->
    Did = did(),
    RegisteredAt = now_ms(),
    Outcome = hear(fact(Did, RegisteredAt, 20 * ?MINUTE), verified(?LISTED)),
    {ok, Entry} = citizen_directory:find(Did),
    [?_assertMatch({ok, _}, Outcome),
     ?_assertEqual(<<"agent">>, maps:get(citizen_kind, Entry)),
     ?_assertEqual(<<"metis">>, maps:get(display_name, Entry)),
     ?_assertEqual([<<"conversation">>], maps:get(offers, Entry)),
     ?_assertEqual(RegisteredAt, maps:get(registered_at, Entry)),
     ?_assertEqual(RegisteredAt + 20 * ?MINUTE, maps:get(expires_at, Entry))].

drops_a_fact_from_an_instance_not_listed(_) ->
    Did = did(),
    [?_assertEqual(dropped, hear(fact(Did, now_ms(), 20 * ?MINUTE), verified(?UNLISTED))),
     ?_assertEqual({error, not_found}, citizen_directory:find(Did))].

%% Delivered at all only when macula's pubsub_strict_publisher_sig is off.
drops_a_fact_whose_signature_did_not_verify(_) ->
    Did = did(),
    Meta = #{publisher => ?LISTED, publisher_verified => false},
    [?_assertEqual(dropped, hear(fact(Did, now_ms(), 20 * ?MINUTE), Meta)),
     ?_assertEqual(dropped, hear(fact(Did, now_ms(), 20 * ?MINUTE), #{publisher => ?LISTED})),
     ?_assertEqual({error, not_found}, citizen_directory:find(Did))].

stores_its_own_expiry_not_the_facts(_) ->
    Did = did(),
    RegisteredAt = now_ms(),
    Fact = (fact(Did, RegisteredAt, ?MINUTE))#{expires_at => RegisteredAt + ?MONTH},
    _ = hear(Fact, verified(?LISTED)),
    {ok, Entry} = citizen_directory:find(Did),
    [?_assertEqual(RegisteredAt + ?MINUTE, maps:get(expires_at, Entry))].

caps_a_ttl_above_twenty_minutes(_) ->
    Did = did(),
    RegisteredAt = now_ms(),
    _ = hear(fact(Did, RegisteredAt, ?MONTH), verified(?LISTED)),
    {ok, Entry} = citizen_directory:find(Did),
    [?_assertEqual(RegisteredAt + 20 * ?MINUTE, maps:get(expires_at, Entry))].

refuses_a_fact_without_registered_at(_) ->
    Did = did(),
    Fact = maps:without([registered_at, ttl_ms], fact(Did, now_ms(), 20 * ?MINUTE)),
    [?_assertEqual({refused, invalid_registered_at}, hear(Fact, verified(?LISTED))),
     ?_assertEqual({error, not_found}, citizen_directory:find(Did))].

refuses_a_registration_more_than_a_minute_ahead(_) ->
    Did = did(),
    [?_assertEqual({refused, registered_at_ahead_of_clock},
                   hear(fact(Did, now_ms() + 2 * ?MINUTE, 20 * ?MINUTE), verified(?LISTED))),
     ?_assertEqual({error, not_found}, citizen_directory:find(Did))].

a_replayed_earlier_registration_replaces_nothing(_) ->
    Did = did(),
    Current = now_ms(),
    _ = hear(fact(Did, Current, 20 * ?MINUTE, <<"current">>), verified(?LISTED)),
    _ = hear(fact(Did, Current - ?MINUTE, 20 * ?MINUTE, <<"replayed">>), verified(?LISTED)),
    {ok, Entry} = citizen_directory:find(Did),
    [?_assertEqual(<<"current">>, maps:get(display_name, Entry)),
     ?_assertEqual(Current, maps:get(registered_at, Entry))].

drops_a_fact_whose_did_is_not_a_did(_) ->
    Fact = (fact(did(), now_ms(), ?MINUTE))#{citizen_did => {text, <<"nope">>}},
    [?_assertEqual({refused, invalid_citizen_did}, hear(Fact, verified(?LISTED)))].

%%------------------------------------------------------------------------------

hear(Fact, Meta) ->
    hear_citizen_presence:take(Fact, Meta, [?LISTED]).

verified(Publisher) ->
    #{publisher => Publisher, publisher_verified => true}.

fact(Did, RegisteredAt, TtlMs) ->
    fact(Did, RegisteredAt, TtlMs, <<"metis">>).

%% The fact exactly as register_presence_responder publishes it.
fact(Did, RegisteredAt, TtlMs, DisplayName) ->
    register_presence_responder:presence_fact(#{
        citizen_did => Did, citizen_kind => <<"agent">>, display_name => DisplayName,
        offers => [<<"conversation">>], registered_at => RegisteredAt,
        ttl_ms => TtlMs, expires_at => RegisteredAt + TtlMs}).

did() -> crypto:strong_rand_bytes(32).

now_ms() -> erlang:system_time(millisecond).
