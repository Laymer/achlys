%%====================================================================
%% @doc achlys constants definitions
%% @end
%%====================================================================

-include_lib("kernel/include/file.hrl").

-export_type([task_targets/0]).
-export_type([task/0]).

%%====================================================================
%% Types
%%====================================================================

-type task_targets() :: [node()] | all.

-type task() :: #{name => atom(),
                    targets => task_targets(),
                    function => function()}.

%%====================================================================
%% Time Intervals (ms)
%%====================================================================

-define(MS , 20).
-define(ONE , 1000).
-define(THREE , 3000).
-define(FIVE , 5000).
-define(TEN , 10000).
-define(HMIN , 30000).
-define(MIN , 60000).
-define(TWOMIN , 120000).
-define(THREEMIN , 180000).

-define(MILLION , 1000000).


%%====================================================================
%% Common Macros
%%====================================================================

-define(TASKS , {<<"tasks">>, state_awset}).

%% Thanks to https://github.com/erszcz
%% Helper macro for declaring children of supervisor
% -define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(SUPFLAGS(Intensity , Period) , #{strategy  => one_for_one
    ,                                    intensity => Intensity
    ,                                    period    => Period
}).

-define(NAV_WORKER , #{id     => achlys_pmod_nav_worker
    , start    => {achlys_pmod_nav_worker , start_link , []}
    , restart  => transient
    , shutdown => 5000
    , type     => worker
    , modules  => [achlys_pmod_nav_worker]
}).

-define(ALS_WORKER , #{id     => achlys_pmod_als_worker
    , start    => {achlys_pmod_als_worker , start_link , []}
    , restart  => transient
    , shutdown => 5000
    , type     => worker
    , modules  => [achlys_pmod_als_worker]
}).

-define(CLEANER_WORKER , #{id     => achlys_cleaner
    , start    => {achlys_cleaner , start_link , []}
    , restart  => permanent
    , shutdown => 5000
    , type     => worker
    , modules  => [achlys_cleaner]
}).

-define(SENSOR_COMMANDER , #{id     => achlys_sensor_commander
    , start    => {achlys_sensor_commander , start_link , []}
    , restart  => permanent
    , shutdown => 5000
    , type     => worker
    , modules  => [achlys_sensor_commander]
}).

-define(TASK_SERVER , #{id     => achlys_task_server
    , start    => {achlys_task_server , start_link , []}
    , restart  => permanent
    , shutdown => 5000
    , type     => worker
    , modules  => [achlys_task_server]
}).
