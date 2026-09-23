%%% @doc The citizens directory: who is on the mesh right now.
%%%
%%% SOFT STATE, ON PURPOSE. Every entry expires within twenty minutes, clients
%%% re-register about every five, and instances federate each registration as a
%%% mesh fact. So the directory lives in an ETS table this process owns, not on
%%% disk: after a restart it is empty for at most one republish interval, then
%%% whole again. Nothing written here outlives the registration that made it.
%%%
%%% ONE WRITER. Every write goes through `admit/2' in this process, which reads
%%% the current live entry, asks the policy whether the incoming registration
%%% wins, and writes it, in one step. Two registrations of one citizen cannot
%%% both read the old entry and both write. Reads go to the table directly.
%%%
%%% Expired entries are invisible at read time, and `sweep/0' (run every minute)
%%% removes them, so memory is bounded by the citizens registered in the last
%%% twenty minutes.
%%%
%%% An entry is an atom-keyed map: citizen_did (32 raw bytes), citizen_kind,
%%% display_name, offers, registered_at, expires_at. Absent fields are omitted.
-module(citizen_directory).

-behaviour(gen_server).

-export([start_link/0, admit/2, find/1, live/0, sweep/0, size/0, is_running/0, to_wire/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, ?MODULE).
-define(SWEEP_MS, 60_000).

-type entry() :: #{citizen_did := <<_:256>>, expires_at := integer(), atom() => term()}.
-type decide() :: fun((entry() | undefined, entry()) -> admit | stale).

-export_type([entry/0]).

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Write `Entry' if `Decide' says it wins against the live entry of the
%% same citizen (`undefined' when there is none).
-spec admit(entry(), decide()) -> admitted | stale.
admit(#{citizen_did := <<_:256>>, expires_at := ExpiresAt} = Entry, Decide)
  when is_integer(ExpiresAt), is_function(Decide, 2) ->
    gen_server:call(?MODULE, {admit, Entry, Decide}).

-spec find(<<_:256>>) -> {ok, entry()} | {error, not_found}.
find(Did) ->
    live_entry(ets:lookup(?TABLE, Did), now_ms()).

%% @doc Every entry that has not expired.
-spec live() -> [entry()].
live() ->
    Now = now_ms(),
    ets:select(?TABLE, [{{'_', '$1', '$2'}, [{'>', '$1', Now}], ['$2']}]).

%% @doc Remove expired entries; answers how many went.
-spec sweep() -> non_neg_integer().
sweep() ->
    gen_server:call(?MODULE, sweep).

%% @doc Entries held, expired ones included until the next sweep.
-spec size() -> non_neg_integer().
size() ->
    ets:info(?TABLE, size).

-spec is_running() -> boolean().
is_running() ->
    is_pid(whereis(?MODULE)).

%% @doc An entry as it goes out in a reply or a fact: text tagged, the DID as
%% lowercase hex text, integers as integers, absent fields omitted.
-spec to_wire(entry()) -> map().
to_wire(#{citizen_did := Did, expires_at := ExpiresAt} = Entry) ->
    Text = maps:map(fun(_K, V) -> {text, V} end,
                    maps:with([citizen_kind, display_name], Entry)),
    Ints = maps:with([registered_at], Entry),
    Offers = [{text, O} || O <- maps:get(offers, Entry, []), is_binary(O)],
    maps:merge(maps:merge(Text, Ints),
               #{citizen_did => citizen_did:to_wire(Did), offers => Offers,
                 expires_at => ExpiresAt}).

%%------------------------------------------------------------------------------

init([]) ->
    ?TABLE = ets:new(?TABLE, [set, protected, named_table, {read_concurrency, true}]),
    erlang:send_after(?SWEEP_MS, self(), sweep),
    {ok, #{}}.

handle_call({admit, #{citizen_did := Did} = Entry, Decide}, _From, St) ->
    Existing = existing(find(Did)),
    {reply, written(Decide(Existing, Entry), Entry), St};
handle_call(sweep, _From, St) ->
    {reply, swept(), St};
handle_call(_Request, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info(sweep, St) ->
    _ = swept(),
    erlang:send_after(?SWEEP_MS, self(), sweep),
    {noreply, St};
handle_info(_Msg, St) ->
    {noreply, St}.

%%------------------------------------------------------------------------------

existing({ok, Entry}) -> Entry;
existing({error, not_found}) -> undefined.

written(admit, #{citizen_did := Did, expires_at := ExpiresAt} = Entry) ->
    true = ets:insert(?TABLE, {Did, ExpiresAt, Entry}),
    admitted;
written(stale, _Entry) ->
    stale.

swept() ->
    Now = now_ms(),
    ets:select_delete(?TABLE, [{{'_', '$1', '_'}, [{'=<', '$1', Now}], [true]}]).

live_entry([{_Did, ExpiresAt, Entry}], Now) when ExpiresAt > Now -> {ok, Entry};
live_entry(_Expired, _Now) -> {error, not_found}.

now_ms() ->
    erlang:system_time(millisecond).
