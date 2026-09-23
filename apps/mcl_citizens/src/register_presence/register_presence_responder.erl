%%% @doc RESPONDER for `mcl-citizens/register_presence'.
%%%
%%% THE CITIZEN IS THE CALLER. macula 12 signs every CALL end to end with the
%%% caller's identity key, verifies that signature here before the handler
%%% runs, and puts the key's node id in the payload as `caller', overwriting
%%% anything the payload sent under that key. Replays are refused by the
%%% request's signed deadline and run-once (caller, request_id). So a
%%% registration is always the caller's own, and no proof travels in the
%%% payload. A `citizen_did' the caller sends anyway must name itself: naming
%%% another DID is the squatting a shared directory must refuse.
%%%
%%% The registration is stamped with this instance's clock as `registered_at',
%%% bounded and written by the same policy every federated fact goes through
%%% (`on_citizen_presence_maybe_admit'), then published so the other instances
%%% hear it. Federation is best-effort: the local write has committed, and the
%%% client's next republish retries it.
-module(register_presence_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2, presence_fact/1]).

%% Twenty minutes against a client republish interval of about five: the 3-4x
%% margin the directory relies on. It is also the most the policy allows.
-define(DEFAULT_TTL_MS, 1_200_000).

init(_Args) -> {ok, []}.

%% macula merges `caller' only into a map payload, so a null or a list arrives
%% bare: refused as the caller's mistake rather than crashed into a retryable
%% temporary_relay_failure.
-spec handle_request(term(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) when is_map(Payload) ->
    Caller = mcl_om_wire:caller(Payload),
    {reply, reply(registrant(Caller, claimed(Payload)), Payload), State};
handle_request(_NotAMap, State) ->
    {reply, refused(invalid_payload), State}.

%% What the payload says the citizen is, if it says anything.
claimed(Payload) ->
    claimed_did(mcl_om_wire:field(citizen_did, Payload)).

claimed_did(undefined) -> unclaimed;
claimed_did(Did) -> citizen_did:from_wire(Did).

registrant(<<_:256>> = Caller, unclaimed) -> {ok, Caller};
registrant(<<_:256>> = Caller, {ok, Caller}) -> {ok, Caller};
registrant(<<_:256>>, {ok, _Other}) -> {error, citizen_did_is_not_the_caller};
registrant(<<_:256>>, {error, _} = Error) -> Error;
registrant(_NoCaller, _Claimed) -> {error, no_verified_caller}.

reply({ok, Did}, Payload) ->
    registered(on_citizen_presence_maybe_admit:handle(presence(Did, Payload)));
reply({error, Reason}, _Payload) ->
    refused(Reason).

registered({ok, #{expires_at := ExpiresAt} = Fields}) ->
    ok = publish(Fields),
    #{ok => 1, expires_at => ExpiresAt};
registered({refused, Reason}) ->
    refused(Reason).

%% The reason goes out as CBOR text; a bare binary reaches non-BEAM callers as
%% bytes.
refused(Reason) ->
    #{ok => 0, error => {text, atom_to_binary(Reason, utf8)}}.

presence(Did, Payload) ->
    #{citizen_did => Did,
      citizen_kind => text(mcl_om_wire:field(citizen_kind, Payload)),
      display_name => text(mcl_om_wire:field(display_name, Payload)),
      offers => offers(mcl_om_wire:field(offers, Payload, [])),
      registered_at => erlang:system_time(millisecond),
      ttl_ms => mcl_om_wire:field(ttl_ms, Payload, ?DEFAULT_TTL_MS)}.

text(Bin) when is_binary(Bin) -> Bin;
text(_NotText) -> undefined.

offers(Offers) when is_list(Offers) -> [O || O <- Offers, is_binary(O)];
offers(_NotAList) -> [].

%% @doc The presence fact for a registration: a directory entry on the wire
%% plus the bounded `ttl_ms'. A receiving instance computes its own expiry from
%% `registered_at' and `ttl_ms'; `expires_at' stays for subscribers that show
%% it, and no instance reads it back.
-spec presence_fact(map()) -> map().
presence_fact(#{ttl_ms := TtlMs} = Fields) ->
    Entry = maps:filter(fun(_K, V) -> V =/= undefined end, maps:remove(ttl_ms, Fields)),
    (citizen_directory:to_wire(Entry))#{ttl_ms => TtlMs}.

%% A dark mesh drops the fact; the registration stands. The realm name was
%% checked at boot, before any call could arrive.
publish(Fields) ->
    Topic = mcl_citizens_facts:presence_topic(mcl_citizens_facts:realm_name()),
    _ = mcl_om_pubsub:publish(Topic, presence_fact(Fields), #{mode => async_log}),
    ok.
