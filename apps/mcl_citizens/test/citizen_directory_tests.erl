%% @doc The directory: soft state in an ETS table its own process owns.
%%
%% Admission runs inside the owner, so deciding whether a registration wins and
%% writing it are one step: two registrations of the same citizen cannot both
%% read the old entry and both write. Expired entries are invisible at read
%% time and removed by the sweep, so memory stays bounded by live citizens.
-module(citizen_directory_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MINUTE, 60_000).

directory_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun admits_and_finds/1,
      fun a_stale_registration_writes_nothing/1,
      fun a_registration_replaces_the_whole_entry/1,
      fun an_expired_entry_is_not_found/1,
      fun live_lists_only_unexpired_entries/1,
      fun the_sweep_removes_expired_entries/1,
      fun decide_sees_only_a_live_entry/1]}.

setup() ->
    {ok, Pid} = citizen_directory:start_link(),
    unlink(Pid),
    Pid.

teardown(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.

admits_and_finds(_) ->
    Did = did(),
    E = entry(Did, now_ms(), <<"metis">>),
    [?_assertEqual(admitted, citizen_directory:admit(E, fun always/2)),
     ?_assertEqual({ok, E}, citizen_directory:find(Did))].

a_stale_registration_writes_nothing(_) ->
    Did = did(),
    E = entry(Did, now_ms(), <<"first">>),
    admitted = citizen_directory:admit(E, fun always/2),
    Later = entry(Did, now_ms(), <<"second">>),
    [?_assertEqual(stale, citizen_directory:admit(Later, fun(_, _) -> stale end)),
     ?_assertEqual({ok, E}, citizen_directory:find(Did))].

%% A field the new registration leaves out is gone, not kept from before.
a_registration_replaces_the_whole_entry(_) ->
    Did = did(),
    admitted = citizen_directory:admit(entry(Did, now_ms(), <<"old name">>), fun always/2),
    Bare = maps:remove(display_name, entry(Did, now_ms() + 1, <<"x">>)),
    admitted = citizen_directory:admit(Bare, fun always/2),
    [?_assertEqual({ok, Bare}, citizen_directory:find(Did))].

an_expired_entry_is_not_found(_) ->
    Did = did(),
    admitted = citizen_directory:admit((entry(Did, now_ms(), <<"x">>))#{expires_at => now_ms() - 1},
                                       fun always/2),
    [?_assertEqual({error, not_found}, citizen_directory:find(Did))].

live_lists_only_unexpired_entries(_) ->
    Live = did(),
    Gone = did(),
    admitted = citizen_directory:admit(entry(Live, now_ms(), <<"live">>), fun always/2),
    admitted = citizen_directory:admit((entry(Gone, now_ms(), <<"gone">>))#{expires_at => now_ms() - 1},
                                       fun always/2),
    [?_assertEqual([Live], [D || #{citizen_did := D} <- citizen_directory:live()])].

the_sweep_removes_expired_entries(_) ->
    Gone = did(),
    Live = did(),
    admitted = citizen_directory:admit((entry(Gone, now_ms(), <<"gone">>))#{expires_at => now_ms() - 1},
                                       fun always/2),
    admitted = citizen_directory:admit(entry(Live, now_ms(), <<"live">>), fun always/2),
    Swept = citizen_directory:sweep(),
    [?_assertEqual(1, Swept),
     ?_assertEqual(1, citizen_directory:size())].

%% An entry that has expired is no standing registration: Decide is shown
%% `undefined' for it, not the dead entry.
decide_sees_only_a_live_entry(_) ->
    Did = did(),
    admitted = citizen_directory:admit((entry(Did, now_ms(), <<"x">>))#{expires_at => now_ms() - 1},
                                       fun always/2),
    Self = self(),
    admitted = citizen_directory:admit(entry(Did, now_ms(), <<"y">>),
                                       fun(Existing, _In) -> Self ! {seen, Existing}, admit end),
    Seen = receive {seen, S} -> S after 1000 -> timeout end,
    [?_assertEqual(undefined, Seen)].

%%------------------------------------------------------------------------------

always(_Existing, _Incoming) -> admit.

entry(Did, RegisteredAt, Name) ->
    #{citizen_did => Did, citizen_kind => <<"agent">>, display_name => Name,
      offers => [<<"conversation">>], registered_at => RegisteredAt,
      expires_at => RegisteredAt + 20 * ?MINUTE}.

did() -> crypto:strong_rand_bytes(32).

now_ms() -> erlang:system_time(millisecond).
