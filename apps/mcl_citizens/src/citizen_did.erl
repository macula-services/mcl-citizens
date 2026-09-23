%%% @doc A citizen DID, at rest and on the wire.
%%%
%%% At rest it is the raw 32-byte node id macula verified as a caller. On the
%%% wire it is lowercase hex TEXT, the form a non-BEAM client can type and read
%%% back; `{text, Bin}' encodes as CBOR text, where a bare binary would reach
%%% those clients as bytes.
-module(citizen_did).

-export([from_wire/1, to_wire/1]).

-spec from_wire(term()) -> {ok, <<_:256>>} | {error, invalid_citizen_did}.
from_wire({text, Text}) -> from_wire(Text);
from_wire(<<_:256>> = Raw) -> {ok, Raw};
from_wire(Hex) when is_binary(Hex), byte_size(Hex) =:= 64 -> decoded(Hex);
from_wire(_Other) -> {error, invalid_citizen_did}.

decoded(Hex) ->
    try {ok, binary:decode_hex(Hex)}
    catch error:badarg -> {error, invalid_citizen_did}
    end.

-spec to_wire(<<_:256>>) -> {text, binary()}.
to_wire(<<_:256>> = Did) -> {text, binary:encode_hex(Did, lowercase)}.
