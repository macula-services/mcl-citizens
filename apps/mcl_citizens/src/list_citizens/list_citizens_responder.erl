%%% @doc RESPONDER for `mcl-citizens/list_citizens'. Open: the directory is a
%%% public phone book, not one citizen's private data.
%%%
%%% IT ANSWERS A PAGE (mcl-citizens#1, threat model on
%%% macula-services/mcl-om#19). The live entries, ordered by `citizen_did',
%%% at most `limit' of them (default 100, at most 200) after the DID named in
%%% `after' (64 hex text). `next' names the last DID on the page when more
%%% remain, and is absent on the last page. Whatever the directory holds, one
%%% reply stays bounded. A payload that is not a map asks for the first page;
%%% a limit or an `after' out of bounds is refused `invalid_page'.
-module(list_citizens_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

-define(DEFAULT_LIMIT, 100).
-define(MAX_LIMIT, 200).

init(_Args) -> {ok, []}.

-spec handle_request(term(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) when is_map(Payload) ->
    {reply, answer(limit(mcl_om_wire:field(limit, Payload, ?DEFAULT_LIMIT)),
                   after_did(mcl_om_wire:field('after', Payload))), State};
handle_request(_NotAMap, State) ->
    handle_request(#{}, State).

limit(N) when is_integer(N), N >= 1, N =< ?MAX_LIMIT -> {ok, N};
limit(_OutOfBounds) -> error.

after_did(undefined) -> {ok, first};
after_did(Hex) when is_binary(Hex), byte_size(Hex) =:= 64 -> did(citizen_did:from_wire(Hex));
after_did(_NotHex) -> error.

did({ok, Did}) -> {ok, Did};
did({error, _}) -> error.

answer({ok, Limit}, {ok, After}) ->
    Following = following(After),
    paged(lists:split(min(Limit, length(Following)), Following));
answer(_Limit, _After) ->
    #{ok => 0, error => {text, <<"invalid_page">>}}.

following(After) ->
    lists:sort([{Did, E} || #{citizen_did := Did} = E <- citizen_directory:live(),
                            beyond(Did, After)]).

beyond(_Did, first) -> true;
beyond(Did, After) -> Did > After.

paged({Page, Rest}) ->
    Reply = #{ok => 1, citizens => [citizen_directory:to_wire(E) || {_Did, E} <- Page]},
    more(Rest, Page, Reply).

more([], _Page, Reply) -> Reply;
more(_Rest, Page, Reply) ->
    {Last, _} = lists:last(Page),
    Reply#{next => citizen_did:to_wire(Last)}.
