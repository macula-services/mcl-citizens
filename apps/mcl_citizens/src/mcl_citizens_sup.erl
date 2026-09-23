%% @doc Supervises the directory and the federation listener.
%%
%% The directory starts first, so a fact heard the moment the subscription
%% lands has somewhere to go. rest_for_one: a directory restart empties the
%% table, and the listener restarts behind it so nothing is admitted into a
%% table that is about to vanish.
-module(mcl_citizens_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => rest_for_one, intensity => 5, period => 10},
          [#{id => citizen_directory,
             start => {citizen_directory, start_link, []}},
           #{id => hear_citizen_presence,
             start => {hear_citizen_presence, start_link, []}}]}}.
