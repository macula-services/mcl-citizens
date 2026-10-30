%% @doc The macula and mcl_om this service is built with, checked down to the
%% patch. A floor, not an exact version: a later compatible release must pass,
%% an earlier one must not.
%%
%% macula 18.0.0: 18 keeps wire 1.0, the wire the flag day moved the fleet to,
%% with calls and streams sealed end to end, and everything 16 added (the
%% revocation bound, macula#118); it adds the caller and source rules
%% (macula#147), which is why this service's presence subscription now names
%% its sources. mcl_om 1.6 is the release whose own base is macula 18: it
%% serves /health on a Unix socket (health_socket), honours `{mesh, required}'
%% in config/sys.config.src (a boot without realm, realm key or pinned seeds
%% is refused, naming each), and refuses the boot of a capability that names no
%% caller (mcl-om#41).
%%
%% THE FLOOR IS PART OF THE GUARD, not decoration: 18.0.0 and 1.6.0 both sort
%% above the old 16.0.0 / 1.4.0, so a floor left behind passes a build this
%% service could not boot on and CI never says a word.
-module(dependency_floors_tests).

-include_lib("eunit/include/eunit.hrl").

macula_floor_test() ->
    ?assert(at_least(vsn(macula), [18, 0, 0])).

mcl_om_floor_test() ->
    ?assert(at_least(vsn(mcl_om), [1, 6, 0])).

%% Whether an "X.Y.Z" version is at least [Major, Minor, Patch].
at_least(Vsn, Floor) ->
    [Major, Minor, Patch | _] = [list_to_integer(P) || P <- string:split(Vsn, ".", all)],
    [Major, Minor, Patch] >= Floor.

vsn(App) ->
    _ = application:load(App),
    {ok, Vsn} = application:get_key(App, vsn),
    Vsn.
