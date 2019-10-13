%%%-------------------------------------------------------------------
%%% @author Igor Kopestenski <igor.kopestenski@uclouvain.be>
%%%     [https://github.com/Laymer/achlys]
%%% @doc
%%% Top level module operating the achlys application
%%% as well as providing the main API to the underlying components.
%%% @end
%%% Created : 06. Nov 2018 20:38
%%%-------------------------------------------------------------------
%%% Joe Armstrong, Co-Creator of Erlang
%%% Dec '17
%%%
%%% You have to remember that any SQL database will be a bottleneck since
%%% there is an impedance mismatch between the way dayt is represented in a
%%% daybase and the way it is represented in the beam VM.
%%%
%%% Databases are basically rectangular tables of cells, where the cells
%%% contain very simple types like strings and integers - every time you access a
%%% row of an external database this list of cells has to be converted to
%%% beam internal data structures - this conversion is extremely expensive.
%%%
%%% The best way to persist data is in a process - then no conversion is needed,
%%% but this is not fault tolerant - so you need to keep a trail of updates
%%% to the data and store this on disk.
%%%
%%% Often you don’t need a database for example you might like to have a system
%%% where you store all the user data as in the file system with “one file per user”
%%% this will scale very nicely - just move the files to a new machine
%%% if you need more capacity.
%%%
%%% Erlang has two primitives term_to_binary and the inverse binary_to_term that
%%% serialise any term and reconstruct it - so storing complex terms on disk
%%% is really easy.
%%%
%%% I have mixed feelings about databases, they are great for aggregate operations
%%% (for example, find all users that have these attributes) but terrible for
%%% operations on individual users (where a single file per user is far better).
%%%
%%% If I were designing a new system I’d go for ‘one file per user’ as much as
%%% possible and try to limit databases for operations over all users.
%%%
%%% If you look at how many programs are designed you’ll see they follow
%%% this principle. Apple stores all images in the file system (hidden a bit)
%%% and has a database with metadata about the files. This is good since
%%% the database is small
%%% and many operations can be performed with minimal use of the database.
%%% What they do not do is put all the data in a database - there are good
%%% reasons for this.
%%%-------------------------------------------------------------------

-module(achlys).
-author("Igor Kopestenski <igor.kopestenski@uclouvain.be>").

-include("achlys.hrl").

%% Application control
-export([start/0]).
-export([stop/0]).

%%====================================================================
%% Task model API
%%====================================================================
-export([get_all_tasks/0]).
-export([bite/1]).
-export([declare/4]).

%% Shortcuts
-export([members/0]).
-export([gc/0]).

%%====================================================================
%% TODO: Binary encoding of values propagated through CRDTs instead
%% of propagating tuples directly in the cluster
%%
%% 32 bits :
%%
%% first 8 bits :
%% [_][_] [_][_]  [_][_] [_][_]
%%                |--------------> 4 bits for node ID : [0][0] [0][0]
%%                |--------------> 4 bits for node ID : [0][0] [0][1]
%%                                                          ...
%%                |--------------> 4 bits for node ID : [1][1] [1][1]
%%        |----|---------> 2 bits for value type : [0][0] => temperature
%%        |----|---------> 2 bits for value type : [0][1] => pressure
%%        |----|---------> 2 bits for value type : [1][0] => light
%%        |----|---------> 2 bits for value type : [1][1] => humidity
%%
%% 8-16 bits :
%% [_][_] [_][_]  [_][_] [_][_]
%%        |-------------> 8 bits for aggregations count : 0 to 255
%%
%% 14-32 bits :
%% [_][_] [_][_]  [_][_] [_][_]  [_][_] [_][_]  [_][_]
%% |-------------> 14 bits for aggregation value : 0 to 262 143
%%====================================================================

%% ===================================================================
%% Entry point functions
%% ===================================================================

%% @doc Start the application.
-spec start() -> ok.
start() ->
    {ok , _} = application:ensure_all_started(achlys) ,
    ok.

%% @doc Stop the Application
-spec stop() -> ok.
stop() ->
    ok = application:stop(achlys) ,
    ok.

%% ===================================================================
%% API
%% ===================================================================

%% @doc Returns current view of all tasks.
-spec get_all_tasks() -> [achlys:task()] | [].
get_all_tasks() ->
    {ok, Set} = lasp:query(?TASKS),
    sets:to_list(Set).

%% @doc Shortcut function exposing the utility function that can be
%% used to pass more readable arguments to create a task model variable
%% instead of binary strings. The ExecType argument can currently not
%% provide a transient mode, a task is executed either once or permanently.
%% Removing the task from the CRDT does not prevent nodes to keep executing it.
%% But similar behavior can be created with a single execution task that
%% specifies a function with several loops. However this does not allow the
%% worker to have full control over the load, since backpressure can be applied
%% by spawning a process that executes a permanent task at a controlled
%% frequency that can be based on any stress parameter. Meanwhile a single
%% execution task could possibly overload the worker, as iterations are
%% embedded inside a single process.
%%
%% When Grow-only Counters and Sets are used, the transient can be achieved
%% using Lasp's monotonic read function to have a distributed treshold.
%%
%%
-spec declare(Name::atom()
    , Targets::[node()] | all
    , ExecType::single | permanent
    , Func::function()) -> task() | erlang:exception().
declare(Name, Targets, ExecType, Func) ->
    achlys_util:declare(Name, Targets, ExecType, Func).

%% @doc Adds the given task in the replicated task set.
%% @see achlys_task_server:add_task/1.
-spec bite(Task :: achlys:task()) -> ok.
bite(Task) ->
    achlys_task_server:add_task(Task).

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Attempts to discover and join other neighboring nodes.
-spec clusterize() -> [atom()].
clusterize() ->
    logger:log(notice , "Cluster formation attempt ~n") ,
    N = seek_neighbors() ,
    Remotes = binary_remotes_to_atoms(N) ,
    Reachable = [R || R <- Remotes
        ,        R =/= node()
        ,        net_adm:ping(R) =:= pong] ,
    clusterize(Reachable).

%% @doc Collect data based on sensors available on Pmod modules and store
%% aggregated values in corresponding Lasp variable.
-spec venom(atom()) -> ok.
venom(Worker) ->
    Worker:run().

%% @doc Returns a list of known remote hostnames
%% that could be potential neighbors.
get_preys() ->
    binary_remotes_to_atoms(seek_neighbors()).

%% @private
binary_remotes_to_atoms([H | T]) ->
    [binary_to_atom(H , utf8) | binary_remotes_to_atoms(T)];
binary_remotes_to_atoms([]) ->
    [].

%% @private
seek_neighbors() ->
    Rc = inet_db:get_rc() ,
    seek_neighbors(Rc).
seek_neighbors([{host , _Addr , N} | T]) ->
    [list_to_bitstring(["achlys@" , N]) | seek_neighbors(T)];
seek_neighbors([{_Arg , _Val} | T]) ->
    seek_neighbors(T);
seek_neighbors([]) ->
    [].

%% @private
join(Host) ->
ok = lasp_peer_service:join(Host),
    {ok, Host}.

%% @private
clusterize([H | Remotes]) ->
    case join(H) of
        {ok , N} ->
            [N | clusterize(Remotes)];
        _ ->
            logger:log(warning , "Failed to join : ~p ~n" , [H]) ,
            clusterize(Remotes)
    end;

clusterize([]) ->
    [].

%% @private
members() ->
    lasp_peer_service:members().

%% @private
gc() ->
    achlys_util:do_gc().

%% @private
join_host(Host) ->
    lasp_peer_service:join(Host).
