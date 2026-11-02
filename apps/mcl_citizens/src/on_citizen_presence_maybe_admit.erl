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
%%% WHAT ONE ENTRY MAY COST IS BOUNDED (mcl-citizens#1, threat model on
%%% macula-services/mcl-om#19). `display_name' is at most 64 bytes,
%%% `citizen_kind' at most 32, `offers' at most 16 of at most 64 bytes each.
%%% Each is checked before anything else, and each must be non-empty UTF-8
%%% with no control character (C0, DEL or C1): one entry that is not valid
%%% text makes every `list_citizens' reply unsendable, so it is refused here,
%%% on both paths, and never written. An absent field stays allowed.
%%%
%%% `with_expiry/2' and `decide/2' are pure: no mesh, no directory, no clock.
-module(on_citizen_presence_maybe_admit).

-export([handle/1, with_expiry/2, decide/2]).

-define(MAX_TTL_MS, 1_200_000).
-define(MAX_AHEAD_MS, 60_000).
-define(MAX_DISPLAY_NAME, 64).
-define(MAX_CITIZEN_KIND, 32).
-define(MAX_OFFERS, 16).
-define(MAX_OFFER, 64).

-type refusal() :: invalid_registered_at | registered_at_ahead_of_clock | invalid_ttl_ms
                 | display_name_too_long | invalid_display_name
                 | citizen_kind_too_long | invalid_citizen_kind
                 | too_many_offers | offer_too_long | invalid_offer.

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

%% @doc `Presence' with its fields checked, its TTL bounded and its expiry
%% computed against `Now', or the reason it is refused.
-spec with_expiry(map(), integer()) -> {ok, map()} | {refused, refusal()}.
with_expiry(Presence, Now) ->
    timed(fields(Presence), Presence, Now).

timed(ok, Presence, Now) ->
    expiring(registered(maps:get(registered_at, Presence, undefined), Now),
             bounded(maps:get(ttl_ms, Presence, undefined)), Presence, Now);
timed(Reason, _Presence, _Now) ->
    {refused, Reason}.

%% `ok', or the reason of the first field that fails, in a fixed order.
fields(Presence) ->
    first([fun() -> text(maps:get(display_name, Presence, undefined), ?MAX_DISPLAY_NAME,
                         display_name_too_long, invalid_display_name) end,
           fun() -> text(maps:get(citizen_kind, Presence, undefined), ?MAX_CITIZEN_KIND,
                         citizen_kind_too_long, invalid_citizen_kind) end,
           fun() -> offers(maps:get(offers, Presence, [])) end]).

first([]) -> ok;
first([Check | Rest]) -> next_check(Check(), Rest).

next_check(ok, Rest) -> first(Rest);
next_check(Reason, _Rest) -> Reason.

%% An absent field is allowed; a present one is bounded text.
text(undefined, _Max, _TooLong, _Invalid) -> ok;
text(Bin, Max, TooLong, _Invalid) when is_binary(Bin), byte_size(Bin) > Max -> TooLong;
text(Bin, _Max, _TooLong, Invalid) -> printable(Bin, Invalid).

printable(<<>>, Invalid) -> Invalid;
printable(Bin, Invalid) when is_binary(Bin) -> chars(unicode:characters_to_list(Bin), Invalid);
printable(_NotText, Invalid) -> Invalid.

chars(Chars, Invalid) when is_list(Chars) ->
    no_control(lists:any(fun control/1, Chars), Invalid);
chars(_NotUtf8, Invalid) ->
    Invalid.

no_control(false, _Invalid) -> ok;
no_control(true, Invalid) -> Invalid.

control(C) -> C < 16#20 orelse (C >= 16#7F andalso C =< 16#9F).

offers(undefined) -> ok;
offers(Offers) when is_list(Offers), length(Offers) > ?MAX_OFFERS -> too_many_offers;
offers(Offers) when is_list(Offers) ->
    first([fun() -> text(O, ?MAX_OFFER, offer_too_long, invalid_offer) end || O <- Offers]);
offers(_NotAList) -> invalid_offer.

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
