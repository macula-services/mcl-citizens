%%% @doc RESPONDER for `mcl-citizens/list_citizens'. Open: the directory is a
%%% public phone book, not one citizen's private data.
-module(list_citizens_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(_Payload, State) ->
    Citizens = [citizen_directory:to_wire(E) || E <- citizen_directory:live()],
    {reply, #{ok => 1, citizens => Citizens}, State}.
