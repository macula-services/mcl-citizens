%% @doc A citizen DID on the wire and at rest. At rest it is the raw 32-byte
%% node id macula verified as a caller; on the wire it is lowercase hex TEXT,
%% the form a non-BEAM client can type and read back.
-module(citizen_did_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HEX, <<"4f769c4e76402f3a0114f00f81a6b255f8f3298a1a9029ea5cf8a25c1463d7a0">>).

raw() -> binary:decode_hex(?HEX).

reads_hex_text_test() ->
    ?assertEqual({ok, raw()}, citizen_did:from_wire({text, ?HEX})).

reads_upper_case_hex_test() ->
    ?assertEqual({ok, raw()}, citizen_did:from_wire({text, string:uppercase(?HEX)})).

reads_bare_hex_test() ->
    ?assertEqual({ok, raw()}, citizen_did:from_wire(?HEX)).

reads_raw_bytes_test() ->
    ?assertEqual({ok, raw()}, citizen_did:from_wire(raw())).

refuses_what_is_not_a_did_test() ->
    [?assertEqual({error, invalid_citizen_did}, citizen_did:from_wire(V))
     || V <- [{text, <<"not-a-did">>}, <<1, 2, 3>>, 42, undefined,
              {text, <<"zz", (binary:part(?HEX, 2, 62))/binary>>}]].

writes_lowercase_hex_text_test() ->
    ?assertEqual({text, ?HEX}, citizen_did:to_wire(raw())).
