%% @doc The wire shape of a citizen: every text field is `{text, Bin}' (CBOR
%% text, so a non-BEAM reader gets a string and not hex), the DID is
%% lowercase hex text, absent fields are omitted, integers stay integers.
-module(citizen_wire_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HEX, <<"4f769c4e76402f3a0114f00f81a6b255f8f3298a1a9029ea5cf8a25c1463d7a0">>).

entry() ->
    #{citizen_did => binary:decode_hex(?HEX), citizen_kind => <<"agent">>,
      display_name => <<"fresh-install-repro">>, offers => [<<"conversation">>],
      registered_at => 1788353847886, expires_at => 1788355047886}.

tags_text_and_hexes_the_did_test() ->
    ?assertEqual(#{citizen_did => {text, ?HEX},
                   citizen_kind => {text, <<"agent">>},
                   display_name => {text, <<"fresh-install-repro">>},
                   offers => [{text, <<"conversation">>}],
                   registered_at => 1788353847886,
                   expires_at => 1788355047886},
                 citizen_directory:to_wire(entry())).

omits_absent_fields_test() ->
    Wire = citizen_directory:to_wire(maps:without([citizen_kind, display_name], entry())),
    ?assertNot(maps:is_key(citizen_kind, Wire)),
    ?assertNot(maps:is_key(display_name, Wire)).

carries_only_integers_text_and_lists_of_text_test() ->
    Bad = [K || {K, V} <- maps:to_list(citizen_directory:to_wire(entry())), not wire_safe(V)],
    ?assertEqual([], Bad).

wire_safe(N) when is_integer(N) -> true;
wire_safe({text, B}) when is_binary(B) -> true;
wire_safe(L) when is_list(L) -> lists:all(fun wire_safe/1, L);
wire_safe(_Other) -> false.
