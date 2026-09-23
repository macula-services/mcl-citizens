%%% @doc POLICY: whether a presence registration is written, and until when.
%%% It arrives either as this instance's own registration
%%% (`register_presence_responder') or as a federated fact from a listed
%%% instance (`hear_citizen_presence'). One code path either way: "should this
%%% be written" has exactly one home.
%%%
%%% THE EXPIRY IS THIS INSTANCE'S OWN ARITHMETIC. A registration carries
%%% `registered_at', stamped by the instance that took the call, and `ttl_ms'.
%%% What is stored expires at registered_at plus the TTL, with the TTL bounded
%%% to twenty minutes and the result never later than twenty minutes from this
%%% instance's clock. An `expires_at' in the input is never read: a fact that
%%% names its own expiry could keep an entry alive for as long as it liked. A
%%% registration stamped more than a minute ahead of this clock is refused, so
%%% an instance whose clock runs fast cannot win against every later
%%% registration until its clock catches up.
%%%
%%% THE LATEST REGISTRATION WINS, by registered_at and not by expiry: an owner
%%% who registers again with a shorter TTL replaces their own entry, and a
%%% replayed older fact replaces nothing.
%%%
%%% `with_expiry/2' and `decide/2' are pure: no mesh, no directory, no clock.
-module(on_citizen_presence_maybe_admit).

-export([handle/1, with_expiry/2, decide/2]).

-define(MAX_TTL_MS, 1_200_000).
-define(MAX_AHEAD_MS, 60_000).

-type refusal() :: invalid_registered_at | registered_at_ahead_of_clock | invalid_ttl_ms.

-export_type([refusal/0]).

%% @doc Write `Presence' if it wins against the live registration of the same
%% citizen. Returns the fields as bounded here, whether or not they won, or the
%% reason they were refused.
-spec handle(map()) -> {ok, map()} | {refused, refusal()}.
handle(Presence) ->
    written(with_expiry(Presence, erlang:system_time(millisecond))).

written({ok, Fields}) ->
    _ = citizen_directory:admit(entry(Fields), fun decide/2),
    {ok, Fields};
written({refused, _Reason} = Refused) ->
    Refused.

%% What is stored: the registration without its ttl_ms, absent fields omitted.
entry(Fields) ->
    maps:filter(fun(_K, V) -> V =/= undefined end, maps:remove(ttl_ms, Fields)).

%% @doc `Presence' with its TTL bounded and its expiry computed against `Now',
%% or the reason it is refused.
-spec with_expiry(map(), integer()) -> {ok, map()} | {refused, refusal()}.
with_expiry(Presence, Now) ->
    expiring(registered(maps:get(registered_at, Presence, undefined), Now),
             bounded(maps:get(ttl_ms, Presence, undefined)), Presence, Now).

registered(RegisteredAt, Now)
  when is_integer(RegisteredAt), RegisteredAt =< Now + ?MAX_AHEAD_MS ->
    {ok, RegisteredAt};
registered(RegisteredAt, _Now) when is_integer(RegisteredAt) ->
    {refused, registered_at_ahead_of_clock};
registered(_RegisteredAt, _Now) ->
    {refused, invalid_registered_at}.

bounded(TtlMs) when is_integer(TtlMs), TtlMs > 0 -> {ok, min(TtlMs, ?MAX_TTL_MS)};
bounded(_TtlMs) -> {refused, invalid_ttl_ms}.

expiring({ok, RegisteredAt}, {ok, TtlMs}, Presence, Now) ->
    {ok, Presence#{ttl_ms => TtlMs,
                   expires_at => min(RegisteredAt + TtlMs, Now + ?MAX_TTL_MS)}};
expiring({refused, _Reason} = Refused, _TtlMs, _Presence, _Now) ->
    Refused;
expiring(_RegisteredAt, {refused, _Reason} = Refused, _Presence, _Now) ->
    Refused.

%% @doc Whether `Incoming' replaces `Existing', the live registration of the
%% same citizen (`undefined' when there is none).
-spec decide(map() | undefined, map()) -> admit | stale.
decide(undefined, _Incoming) ->
    admit;
decide(#{registered_at := Current}, #{registered_at := Incoming}) when Incoming >= Current ->
    admit;
decide(_Existing, _Incoming) ->
    stale.
