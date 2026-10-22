%% @doc The macula and mcl_om this service is built with, checked down to the
%% patch. A floor, not an exact version: a later compatible release must pass,
%% an earlier one must not.
%%
%% macula 16.0.0: 16 keeps wire 1.0, the wire the flag day moved the fleet to,
%% with calls and streams sealed end to end; what it adds is the revocation
%% bound (macula#118). mcl_om 1.4 is the release whose own base is macula 16;
%% it serves /health on a Unix socket (health_socket) and honours
%% `{mesh, required}' in config/sys.config.src (a boot without realm, realm
%% key or pinned seeds is refused, naming each).
-module(dependency_floors_tests).

-include_lib("eunit/include/eunit.hrl").

macula_floor_test() ->
    ?assert(at_least(vsn(macula), [16, 0, 0])).

mcl_om_floor_test() ->
    ?assert(at_least(vsn(mcl_om), [1, 4, 0])).

%% Whether an "X.Y.Z" version is at least [Major, Minor, Patch].
at_least(Vsn, Floor) ->
    [Major, Minor, Patch | _] = [list_to_integer(P) || P <- string:split(Vsn, ".", all)],
    [Major, Minor, Patch] >= Floor.

vsn(App) ->
    _ = application:load(App),
    {ok, Vsn} = application:get_key(App, vsn),
    Vsn.
