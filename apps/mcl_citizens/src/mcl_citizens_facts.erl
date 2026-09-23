%%% @doc The public contract: the one fact this service publishes and hears.
%%%
%%%   citizen_presence_registered_v1  a citizen registered with an instance;
%%%                                   the other instances admit it
%%%
%%% The topic is a canonical macula app fact owned by org `mcl-citizens', app
%%% `citizens', domain `directory', for example
%%% `io.macula/mcl-citizens/citizens/directory/citizen_presence_registered_v1'.
%%% The org segment is the schema owner and is fixed here, not deploy config.
%%%
%%% WHO PUBLISHED A FACT IS NOT IN THE PAYLOAD. macula delivers every event
%%% with the publisher its link verified, and the listener attributes by that.
-module(mcl_citizens_facts).

-export([presence_topic/1, realm_name/0, check_realm_name/0, check_realm_name/2,
         presence_publishers/0]).

-define(APP, mcl_citizens).

-spec presence_topic(binary()) -> binary().
presence_topic(RealmName) ->
    macula_topic:app_fact(RealmName, <<"mcl-citizens">>, <<"citizens">>, <<"directory">>,
                          <<"citizen_presence_registered">>, 1).

%% @doc The realm name the topic carries, from `MCL_REALM_NAME'.
-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(?APP, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_citizens_realm_name_unset, realm_name}).

%% @doc Refuse to start when the configured realm name is not the realm the
%% pool publishes in: the facts would go where nobody subscribed, and an
%% instance that federates with nobody looks exactly like a quiet one.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other) -> error({mcl_citizens_realm_unset, Name, Other}).

-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag) -> error({mcl_citizens_realm_name_mismatch, Name, Tag}).

%% @doc The instances whose presence facts are admitted, as raw node ids, from
%% `MCL_CITIZENS_PRESENCE_PUBLISHERS' (64 hex each, comma separated). This
%% instance's own id is optional: it writes its own registrations before
%% publishing them. Missing or malformed stops the node.
-spec presence_publishers() -> [<<_:256>>].
presence_publishers() ->
    publishers(application:get_env(?APP, presence_publishers)).

publishers({ok, Ids}) when is_list(Ids) ->
    [node_id(string:trim(Id)) || Id <- string:split(list_to_binary(Ids), <<",">>, all)];
publishers({ok, _NotAString}) ->
    error({invalid_presence_publishers, not_a_string});
publishers(undefined) ->
    error({invalid_presence_publishers, missing}).

node_id(Hex) ->
    hex_node_id(re:run(Hex, <<"\\A[0-9a-fA-F]{64}\\z">>, [{capture, none}]), Hex).

hex_node_id(match, Hex) -> binary:decode_hex(Hex);
hex_node_id(nomatch, _Hex) -> error({invalid_presence_publishers, not_64_hex}).
