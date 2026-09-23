%%% @doc The public contract: the presence fact's topic, the realm name it is
%%% built from, and the instances whose facts are heard.
-module(mcl_citizens_facts_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_citizens).

%% A canonical macula app fact owned by org mcl-citizens.
presence_topic_is_an_app_fact_of_this_org_test() ->
    ?assertEqual(macula_topic:app_fact(<<"io.macula">>, <<"mcl-citizens">>, <<"citizens">>,
                                       <<"directory">>, <<"citizen_presence_registered">>, 1),
                 mcl_citizens_facts:presence_topic(<<"io.macula">>)).

%% The topic carries the realm NAME and the pool publishes in the realm TAG;
%% a name that does not hash to the tag publishes where nobody listens.
realm_name_must_hash_to_the_realm_tag_test() ->
    Tag = crypto:hash(sha256, <<"io.macula">>),
    ?assertEqual(ok, mcl_citizens_facts:check_realm_name(<<"io.macula">>, Tag)),
    ?assertError({mcl_citizens_realm_name_mismatch, <<"io.maculaX">>, Tag},
                 mcl_citizens_facts:check_realm_name(<<"io.maculaX">>, Tag)).

realm_name_is_required_test() ->
    ?assertError({mcl_citizens_realm_name_unset, realm_name},
                 with_env(realm_name, "", fun mcl_citizens_facts:realm_name/0)),
    ?assertEqual(<<"io.macula">>,
                 with_env(realm_name, "io.macula", fun mcl_citizens_facts:realm_name/0)).

%% Hex in either case, spaces around the commas allowed.
reads_the_configured_instances_test() ->
    Ids = binary_to_list(<<(binary:encode_hex(<<1:256>>, lowercase))/binary, ", ",
                           (binary:encode_hex(<<2:256>>, uppercase))/binary>>),
    ?assertEqual([<<1:256>>, <<2:256>>],
                 with_env(presence_publishers, Ids, fun mcl_citizens_facts:presence_publishers/0)).

%% Read at boot: one that hears no instance, or the wrong ones, looks healthy
%% and is not, so these stop the node.
refuses_a_missing_or_malformed_instance_list_test() ->
    Good = binary:encode_hex(<<1:256>>, lowercase),
    ?assertError({invalid_presence_publishers, missing},
                 with_env(presence_publishers, unset, fun mcl_citizens_facts:presence_publishers/0)),
    [?assertError({invalid_presence_publishers, not_64_hex},
                  with_env(presence_publishers, binary_to_list(Ids),
                           fun mcl_citizens_facts:presence_publishers/0))
     || Ids <- [<<>>, <<"0">>, binary:part(Good, 0, 63), <<Good/binary, "0">>,
                <<"zz", (binary:part(Good, 2, 62))/binary>>,
                <<Good/binary, ",">>, <<Good/binary, ",,", Good/binary>>]].

with_env(Key, Value, Fun) ->
    _ = application:load(?APP),
    ok = set(Key, Value),
    try Fun()
    after application:unset_env(?APP, Key)
    end.

set(Key, unset) -> application:unset_env(?APP, Key);
set(Key, Value) -> application:set_env(?APP, Key, Value).
