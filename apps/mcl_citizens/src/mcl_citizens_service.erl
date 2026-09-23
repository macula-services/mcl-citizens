%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
-module(mcl_citizens_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"mcl-citizens">>,
      version => <<"0.1.0">>,
      description => <<"The citizens directory for the Macula mesh: who exists, federated across instances by mesh facts">>}.

%% The realm name the fact topic carries is checked against the realm the pool
%% publishes in before anything starts: a mismatch publishes where nobody
%% subscribed, and looks exactly like a quiet directory.
start(_Opts) ->
    ok = mcl_citizens_facts:check_realm_name(),
    mcl_citizens_sup:start_link().

stop(_State) -> ok.

%% Down without the directory, since nothing can be registered or read.
%% Degraded while federation is not subscribed: this instance still serves its
%% own registrations but hears no other instance. A dark mesh is therefore
%% degraded, not down.
health() ->
    directory(citizen_directory:is_running()).

directory(false) -> {down, directory_not_running};
directory(true) -> hearing(hear_citizen_presence:subscribed()).

hearing(true) -> ok;
hearing(false) -> {degraded, not_subscribed_to_presence}.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. On the wire each is
%% `mcl-citizens/<name>': mcl_om prefixes the org from sys.config.
%%
%% ALL OPEN, deliberately. list_citizens and get_citizen read a public phone
%% book. register_presence registers the CALL's verified caller and nobody
%% else, so it needs no token either: macula has already proved who is asking.
capabilities() ->
    [#{name => <<"register_presence">>, version => 1,
       handler => {register_presence_responder, []}, auth => open},
     #{name => <<"list_citizens">>, version => 1,
       handler => {list_citizens_responder, []}, auth => open},
     #{name => <<"get_citizen">>, version => 1,
       handler => {get_citizen_responder, []}, auth => open}].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-citizens">>,
      actions => [],
      resources => [],
      ttl_days => 30}.
