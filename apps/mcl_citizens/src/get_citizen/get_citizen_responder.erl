%%% @doc RESPONDER for `mcl-citizens/get_citizen'. Open: the directory is a
%%% public phone book, not one citizen's private data.
-module(get_citizen_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    Did = citizen_did:from_wire(mcl_om_wire:field(citizen_did, Payload)),
    {reply, fetched(looked_up(Did)), State}.

looked_up({ok, Did}) -> citizen_directory:find(Did);
looked_up({error, _} = Error) -> Error.

%% Errors go out as CBOR text; a bare binary reaches non-BEAM callers as bytes.
fetched({ok, Entry}) -> #{ok => 1, citizen => citizen_directory:to_wire(Entry)};
fetched({error, Reason}) -> #{ok => 0, error => {text, atom_to_binary(Reason, utf8)}}.
