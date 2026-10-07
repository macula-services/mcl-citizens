%% @doc The macula and mcl_om this service is built with, checked down to the
%% patch. A floor, not an exact version: a later compatible release must pass,
%% an earlier one must not.
%%
%% macula 14.2.1: the current SDK base (#2), with calls and streams sealed end to
%% end and a stream's `confidential' kept (macula-io/macula#85); seed() still
%% names expected_node_id. mcl_om 0.38 is the release on macula 14, and still
%% honours `{mesh, required}' in config/sys.config.src (a boot without realm,
%% realm key or pinned seeds is refused, naming each).
-module(dependency_floors_tests).

-include_lib("eunit/include/eunit.hrl").

macula_floor_test() ->
    ?assert(at_least(vsn(macula), [14, 2, 1])).

mcl_om_floor_test() ->
    ?assert(at_least(vsn(mcl_om), [0, 38, 0])).

%% Whether an "X.Y.Z" version is at least [Major, Minor, Patch].
at_least(Vsn, Floor) ->
    [Major, Minor, Patch | _] = [list_to_integer(P) || P <- string:split(Vsn, ".", all)],
    [Major, Minor, Patch] >= Floor.

vsn(App) ->
    _ = application:load(App),
    {ok, Vsn} = application:get_key(App, vsn),
    Vsn.
