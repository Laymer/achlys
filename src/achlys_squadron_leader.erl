%%%-------------------------------------------------------------------
%%% @author Igor Kopestenski <igor.kopestenski@uclouvain.be>
%%%     [https://github.com/Laymer/achlys]
%%% 2018, Universite Catholique de Louvain
%%% @doc
%%%
%%% @end
%%% Created : 13. Dec 2018 19:30
%%%-------------------------------------------------------------------
-module(achlys_squadron_leader).
-author("Igor Kopestenski <igor.kopestenski@uclouvain.be>").

-behaviour(gen_server).

-include("achlys.hrl").

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1 ,
         handle_call/3 ,
         handle_cast/2 ,
         handle_info/2 ,
         terminate/2 ,
         code_change/3]).

%%====================================================================
%% Macros
%%====================================================================

-define(SERVER , ?MODULE).

%%====================================================================
%% Records
%%====================================================================

-record(state , {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok , Pid :: pid()} | ignore | {error , Reason :: term()}).
start_link() ->
    gen_server:start_link({local , ?SERVER} , ?MODULE , [] , []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok , State :: #state{}} | {ok , State :: #state{} , timeout() | hibernate} |
    {stop , Reason :: term()} | ignore).
init([]) ->
    logger:log(notice , "Initializing cluster maintainer. ~n") ,
    schedule_ping(),
    % erlang:send_after(?TEN , ?SERVER , formation) ,
    {ok , #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term() , From :: {pid() , Tag :: term()} ,
                  State :: #state{}) ->
                     {reply , Reply :: term() , NewState :: #state{}} |
                     {reply , Reply :: term() , NewState :: #state{} , timeout() | hibernate} |
                     {noreply , NewState :: #state{}} |
                     {noreply , NewState :: #state{} , timeout() | hibernate} |
                     {stop , Reason :: term() , Reply :: term() , NewState :: #state{}} |
                     {stop , Reason :: term() , NewState :: #state{}}).
handle_call(_Request , _From , State) ->
    {reply , ok , State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term() , State :: #state{}) ->
    {noreply , NewState :: #state{}} |
    {noreply , NewState :: #state{} , timeout() | hibernate} |
    {stop , Reason :: term() , NewState :: #state{}}).
handle_cast(_Request , State) ->
    {noreply , State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term() , State :: #state{}) ->
    {noreply , NewState :: #state{}} |
    {noreply , NewState :: #state{} , timeout() | hibernate} |
    {stop , Reason :: term() , NewState :: #state{}}).
handle_info(formation , State) ->
    _ = achlys:clusterize() ,
    % _ = achlys:contagion() ,
    erlang:send_after(?MIN , ?SERVER , formation) ,
    % {noreply , State, hibernate};
    {noreply , State};

handle_info(ping , State) ->
    L = pinger() ,
    % _ = achlys:contagion() ,
    erlang:send_after(15000 , ?SERVER , ping) ,
    % {noreply , State, hibernate};
    {noreply , State};

handle_info(_Info , State) ->
    {noreply , State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown , term()} | term()) ,
                State :: #state{}) -> term()).
terminate(_Reason , _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down , term()} , State :: #state{} ,
                  Extra :: term()) ->
                     {ok , NewState :: #state{}} | {error , Reason :: term()}).
code_change(_OldVsn , State , _Extra) ->
    {ok , State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%%  Cluster pinger
%% @spec pinger() -> {ok , Reached :: [node()]} | {error , Reason :: term()})
%% @end
%%--------------------------------------------------------------------
-spec(pinger() ->
    {ok , Reached :: [node()]} | {error , Reason :: term()}).
pinger() ->
    Self = node(),
    L = achlys_config:get(boards, []),
    Reached = [ N || N <- L
                    , net_adm:ping(N) =:= pong
                    , N =/= Self ],
    pinger(Reached).
-spec(pinger([node()]) ->
    {ok , Reached :: [node()]} | {error , Reason :: term()}).
pinger(Reached) ->
    L = [ N || N <- Reached, lasp_peer_service:join(N) =:= ok ],
    case length(L) < Reached of
        true ->
            logger:log(critical, "Reachable : ~p ~n", [Reached]),
            logger:log(critical, "Joined : ~p ~n", [L]),
            Reached -- L;
        _ ->
            L
    end.

schedule_ping() ->
    % erlang:send_after(15000 , ?SERVER , ping).
    erlang:send_after(15000 , ?SERVER , formation).