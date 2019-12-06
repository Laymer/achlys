-module(compute_pi).

-behaviour(gen_server).

-export([start_link/0]).
-export([schedule_task/0]).
-export([debug/0]).
-export([
    init/1 ,
    handle_call/3 ,
    handle_cast/2 ,
    handle_info/2 ,
    terminate/2 ,
    code_change/3
]).

-define(SERVER, ?MODULE).

-record(state, {}).

start_link() ->
    gen_server:start_link({local , ?SERVER} , ?MODULE , [] , []).

init([]) ->
    {ok , #state{}}.

handle_call(_Request, _From , State) ->
    {reply , ok , State}.

handle_cast(_Request, State) ->
    {noreply , State}.

handle_info(_Info, State) ->
    case _Info of
        {task, Task} -> 
            io:format("Starting task ~n", []),
            achlys:bite(Task)
    end,
    {noreply , State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok , State}.

schedule_task() ->
    Task = achlys:declare(mytask, all, single, fun() ->

        % Declare variable :

        Type = state_gset,
        Set = {<<"set">>, Type},
        lasp:declare(Set, Type),

        % Add listeners :

        lasp:stream(Set, fun(S) ->
            R = lists:foldl(fun(Current, Acc) ->
                    case Current of #{n := N1, success := S1} ->
                        case Acc of #{n := N2, success := S2} -> #{
                            n => N1 + N2,
                            success => S1 + S2
                        }
                        end
                    end
                end,
                #{n => 0, success => 0},
                sets:to_list(S)
            ),
            case R of #{n := N, success := Success} ->
                io:format("Grow Only Set : ~p~n", [S]),
                io:format("Results: ~p~n", [R]),
                io:format("PI ≃ ~p~n", [4 * Success / N])
            end
        end),

        % Helper functions :

        GetRandomPoint = fun() -> {
            rand:uniform(),
            rand:uniform()
        } end,

        GetDistance = fun(Point) -> 
            case Point of {X, Y} ->
                math:sqrt(X * X + Y * Y)
            end
        end,

        % Sampling :

        N = 450,
        Success = lists:foldl(fun(_, Count) -> 
            case GetDistance(GetRandomPoint()) of
                Distance when Distance =< 1 -> Count + 1;
                _ -> Count
            end    
        end, 0, lists:seq(1, N)),

        % Update :

        lasp:update(Set, {add, #{
            n => N,
            success => Success
        }}, self())
    end),

    erlang:send_after(100, ?SERVER, {task, Task}),
    ok.

debug() ->
    Set = achlys_util:query({<<"set">>, state_gset}),
    io:format("Set: ~p~n", [Set]).