%%% @doc What one citizen's entry may cost, and what a `list_citizens' reply
%%% may hold (mcl-citizens#1, threat model on macula-services/mcl-om#19).
%%%
%%% A1: `display_name' (64 bytes), `citizen_kind' (32 bytes) and `offers' (16
%%% of 64 bytes each) are bounded, at the limit admitted and one over refused
%%% with a named reason, writing nothing. A2: each must be UTF-8 with no
%%% control character, because one entry that is not makes every
%%% `list_citizens' reply unsendable (`macula_frame:check_payload/1'). Both
%%% hold on the two paths into the policy: a caller's own CALL and a federated
%%% fact. A3: `list_citizens' answers a page, bounded whatever the directory
%%% holds, and the pages cover it.
-module(presence_bounds_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NOW, 1_788_000_000_000).
-define(LISTED, <<16#11:256>>).

%%------------------------------------------------------------------------------
%% The policy, pure: on_citizen_presence_maybe_admit:with_expiry/2
%%------------------------------------------------------------------------------

presence(Fields) ->
    maps:merge(#{citizen_did => <<7:256>>, registered_at => ?NOW, ttl_ms => 60_000}, Fields).

verdict(Fields) ->
    case on_citizen_presence_maybe_admit:with_expiry(presence(Fields), ?NOW) of
        {ok, _} -> ok;
        {refused, Reason} -> Reason
    end.

a(N) -> binary:copy(<<"a">>, N).

at_the_limits_a_presence_is_admitted_test() ->
    ?assertEqual(ok, verdict(#{display_name => a(64), citizen_kind => a(32),
                               offers => [a(64) || _ <- lists:seq(1, 16)]})),
    %% Multi-byte text counts its bytes: 32 two-byte characters are 64 bytes.
    ?assertEqual(ok, verdict(#{display_name => binary:copy(<<"é"/utf8>>, 32)})),
    %% Every field stays optional.
    ?assertEqual(ok, verdict(#{})),
    ?assertEqual(ok, verdict(#{offers => []})).

one_over_a_limit_is_refused_by_name_test() ->
    [?assertEqual({Why, Why}, {Why, verdict(Fields)})
     || {Why, Fields} <- [{display_name_too_long, #{display_name => a(65)}},
                          {display_name_too_long, #{display_name => binary:copy(<<"é"/utf8>>, 33)}},
                          {citizen_kind_too_long, #{citizen_kind => a(33)}},
                          {too_many_offers, #{offers => [<<"x">> || _ <- lists:seq(1, 17)]}},
                          {offer_too_long, #{offers => [<<"x">>, a(65)]}}]].

text_that_would_poison_the_list_is_refused_test() ->
    Bad = [<<255, 254>>, <<"ok", 16#c3>>, <<"tab\there">>, <<"nul", 0>>, <<"del", 127>>,
           <<"c1", 16#c2, 16#85>>],
    [?assertEqual({B, invalid_display_name}, {B, verdict(#{display_name => B})}) || B <- Bad],
    [?assertEqual({B, invalid_citizen_kind}, {B, verdict(#{citizen_kind => B})}) || B <- Bad],
    [?assertEqual({B, invalid_offer}, {B, verdict(#{offers => [<<"fine">>, B]})}) || B <- Bad],
    ?assertEqual(invalid_display_name, verdict(#{display_name => <<>>})),
    ?assertEqual(invalid_offer, verdict(#{offers => [<<>>]})).

%%------------------------------------------------------------------------------
%% Both paths, against a running directory
%%------------------------------------------------------------------------------

paths_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun a_call_over_a_limit_is_refused_and_writes_nothing/1,
      fun a_call_with_poisoned_text_is_refused_and_writes_nothing/1,
      fun a_federated_fact_over_a_limit_is_refused_and_writes_nothing/1,
      fun the_list_stays_sendable_after_a_poisoned_attempt/1]}.

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

call(Caller, Fields) ->
    {reply, Reply, []} =
        register_presence_responder:handle_request(maps:merge(#{caller => Caller}, Fields), []),
    Reply.

a_call_over_a_limit_is_refused_and_writes_nothing(_) ->
    Caller = crypto:strong_rand_bytes(32),
    Reply = call(Caller, #{display_name => {text, a(65)}}),
    [?_assertEqual(#{ok => 0, error => {text, <<"display_name_too_long">>}}, Reply),
     ?_assertEqual({error, not_found}, citizen_directory:find(Caller))].

a_call_with_poisoned_text_is_refused_and_writes_nothing(_) ->
    Caller = crypto:strong_rand_bytes(32),
    Reply = call(Caller, #{offers => [{text, <<"conversation">>}, {text, <<255>>}]}),
    [?_assertEqual(#{ok => 0, error => {text, <<"invalid_offer">>}}, Reply),
     ?_assertEqual({error, not_found}, citizen_directory:find(Caller))].

a_federated_fact_over_a_limit_is_refused_and_writes_nothing(_) ->
    Did = crypto:strong_rand_bytes(32),
    Fact = #{citizen_did => {text, binary:encode_hex(Did, lowercase)},
             citizen_kind => {text, a(33)},
             registered_at => erlang:system_time(millisecond), ttl_ms => 60_000},
    Meta = #{publisher_verified => true, publisher => ?LISTED},
    [?_assertEqual({refused, citizen_kind_too_long}, hear_citizen_presence:take(Fact, Meta, [?LISTED])),
     ?_assertEqual({error, not_found}, citizen_directory:find(Did))].

the_list_stays_sendable_after_a_poisoned_attempt(_) ->
    Caller = crypto:strong_rand_bytes(32),
    #{ok := 1} = call(Caller, #{display_name => {text, <<"metis">>}}),
    #{ok := 0} = call(crypto:strong_rand_bytes(32), #{display_name => {text, <<255, 254>>}}),
    {reply, Listed, []} = list_citizens_responder:handle_request(#{}, []),
    [?_assertEqual(ok, macula_frame:check_payload(Listed)),
     ?_assertMatch(#{ok := 1, citizens := [_]}, Listed)].

%%------------------------------------------------------------------------------
%% A3: list_citizens answers a page
%%------------------------------------------------------------------------------

pages_test_() ->
    {setup,
     fun() -> Pid = setup(), [admit(N) || N <- lists:seq(1, 250)], Pid end,
     fun teardown/1,
     fun(_) ->
         [?_test(a_bare_call_answers_the_first_hundred()),
          ?_test(a_limit_bounds_the_page()),
          ?_test(the_pages_cover_the_directory_once_in_order()),
          ?_test(a_page_out_of_bounds_is_refused())]
     end}.

admit(N) ->
    Now = erlang:system_time(millisecond),
    admitted = citizen_directory:admit(#{citizen_did => <<N:256>>, display_name => a(64),
                                         registered_at => Now, expires_at => Now + 600_000},
                                       fun(_, _) -> admit end).

list(Payload) ->
    {reply, Reply, []} = list_citizens_responder:handle_request(Payload, []),
    Reply.

dids(#{citizens := Citizens}) -> [D || #{citizen_did := {text, D}} <- Citizens].

a_bare_call_answers_the_first_hundred() ->
    [?assertMatch(#{ok := 1, next := {text, _}}, list(P)) || P <- [#{}, null, []]],
    ?assertEqual(100, length(dids(list(#{})))).

a_limit_bounds_the_page() ->
    ?assertEqual(1, length(dids(list(#{limit => 1})))),
    ?assertEqual(200, length(dids(list(#{limit => 200})))).

%% Ordered by citizen_did; `next' is the last one on the page, and the last
%% page carries no `next'.
the_pages_cover_the_directory_once_in_order() ->
    Pages = pages(#{limit => 200}, []),
    All = lists:append([dids(P) || P <- Pages]),
    ?assertEqual(2, length(Pages)),
    ?assertEqual(lists:sort(All), All),
    ?assertEqual([binary:encode_hex(<<N:256>>, lowercase) || N <- lists:seq(1, 250)], All),
    ?assertNot(maps:is_key(next, lists:last(Pages))),
    [?assertEqual(ok, macula_frame:check_payload(P)) || P <- Pages].

pages(Payload, Acc) ->
    Page = list(Payload),
    next(maps:get(next, Page, done), [Page | Acc]).

next(done, Acc) -> lists:reverse(Acc);
next(After, Acc) -> pages(#{limit => 200, 'after' => After}, Acc).

a_page_out_of_bounds_is_refused() ->
    [?assertEqual({P, #{ok => 0, error => {text, <<"invalid_page">>}}}, {P, list(P)})
     || P <- [#{limit => 0}, #{limit => 201}, #{limit => {text, <<"5">>}},
              #{'after' => {text, <<"not-hex">>}}, #{'after' => 42}]].
