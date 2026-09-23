%%% @doc Hears the other mcl-citizens instances: the federation half of the
%%% directory.
%%%
%%% Subscribes to the `citizen_presence_registered' fact. ONLY THE LISTED
%%% INSTANCES ARE HEARD: anyone in the realm can publish on that topic, and a
%%% fact carries no signature from the citizen, so it is worth exactly what the
%%% instance that published it checked, which is the citizen's own verified
%%% CALL. A fact reaches the policy only when macula verified its publisher
%%% signature and the publisher is one of the configured instance node ids.
%%% Everything else is dropped here and counted, and the count is logged once
%%% a minute, never per fact.
%%%
%%% Re-subscribes when the subscription goes away, and retries while the mesh
%%% is dark. /health reports degraded until it holds.
-module(hear_citizen_presence).

-behaviour(gen_server).

-export([start_link/0, subscribed/0, take/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(RESUBSCRIBE_MS, 5_000).
-define(REPORT_MS, 60_000).

-record(st, {topic :: binary(),
             publishers :: [<<_:256>>],
             ref :: reference() | undefined,
             dropped = #{} :: #{atom() => pos_integer()}}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Whether the presence subscription is held. False when not running.
-spec subscribed() -> boolean().
subscribed() ->
    try gen_server:call(?MODULE, subscribed, 1000)
    catch exit:_ -> false
    end.

%% @doc One fact, as heard: dropped unless its publisher verified and is
%% listed, otherwise the policy's verdict on it.
-spec take(map(), map(), [<<_:256>>]) ->
    {ok, map()} | {refused, atom()} | dropped.
take(Fact, Meta, Publishers) ->
    heard(listed(Meta, Publishers), Fact).

%% The instance list and the realm name are read first: without valid ones this
%% raises and the node does not boot.
init([]) ->
    Publishers = mcl_citizens_facts:presence_publishers(),
    Topic = mcl_citizens_facts:presence_topic(mcl_citizens_facts:realm_name()),
    self() ! subscribe,
    erlang:send_after(?REPORT_MS, self(), report),
    {ok, #st{topic = Topic, publishers = Publishers}}.

handle_call(subscribed, _From, #st{ref = Ref} = St) ->
    {reply, is_reference(Ref), St};
handle_call(_Request, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, subscribe(mcl_om:mesh_handles(), St)};
handle_info({macula_event, Ref, _Topic, Fact, Meta}, #st{ref = Ref, publishers = Pubs} = St) ->
    {noreply, counted(take(Fact, Meta, Pubs), St)};
handle_info({macula_event_gone, Ref, _Reason}, #st{ref = Ref} = St) ->
    self() ! subscribe,
    {noreply, St#st{ref = undefined}};
handle_info(report, St) ->
    erlang:send_after(?REPORT_MS, self(), report),
    {noreply, reported(St)};
handle_info(_Info, St) ->
    {noreply, St}.

%%------------------------------------------------------------------------------

subscribe({ok, Pool, Realm}, #st{topic = Topic, ref = undefined} = St) ->
    held(macula:subscribe(Pool, Realm, Topic, self()), St);
subscribe({ok, _Pool, _Realm}, St) ->
    St;
subscribe({error, mesh_unavailable}, St) ->
    retry(St).

held({ok, Ref}, St) ->
    St#st{ref = Ref};
held(Error, #st{topic = Topic} = St) ->
    logger:warning("[citizens] subscribing to ~s failed, retrying: ~p", [Topic, Error]),
    retry(St).

retry(St) ->
    erlang:send_after(?RESUBSCRIBE_MS, self(), subscribe),
    St.

listed(#{publisher_verified := true, publisher := Publisher}, Publishers) ->
    lists:member(Publisher, Publishers);
listed(_Meta, _Publishers) ->
    false.

heard(true, Fact) -> admitted(presence(Fact));
heard(false, _Fact) -> dropped.

admitted({ok, Presence}) -> on_citizen_presence_maybe_admit:handle(Presence);
admitted({error, Reason}) -> {refused, Reason}.

%% The fact's expires_at is deliberately not read: the policy computes the
%% expiry from registered_at and ttl_ms.
presence(Fact) ->
    presence_of(citizen_did:from_wire(mcl_om_wire:field(citizen_did, Fact)), Fact).

presence_of({ok, Did}, Fact) ->
    {ok, #{citizen_did => Did,
           citizen_kind => text(mcl_om_wire:field(citizen_kind, Fact)),
           display_name => text(mcl_om_wire:field(display_name, Fact)),
           offers => offers(mcl_om_wire:field(offers, Fact, [])),
           registered_at => mcl_om_wire:field(registered_at, Fact),
           ttl_ms => mcl_om_wire:field(ttl_ms, Fact)}};
presence_of({error, _} = Error, _Fact) ->
    Error.

text(Bin) when is_binary(Bin) -> Bin;
text(_NotText) -> undefined.

offers(Offers) when is_list(Offers) -> [O || O <- Offers, is_binary(O)];
offers(_NotAList) -> [].

counted({ok, _Fields}, St) -> St;
counted({refused, Reason}, St) -> count(Reason, St);
counted(dropped, St) -> count(unlisted_or_unverified_publisher, St).

count(Reason, #st{dropped = D} = St) ->
    St#st{dropped = maps:update_with(Reason, fun(N) -> N + 1 end, 1, D)}.

reported(#st{dropped = D} = St) when map_size(D) =:= 0 ->
    St;
reported(#st{dropped = D} = St) ->
    logger:warning("[citizens] presence facts not taken in the last minute: ~p", [D]),
    St#st{dropped = #{}}.
