-module(esubscribe_SUITE).

-include_lib("esubscribe.hrl").
-include_lib("esubscribe_test.hrl").


-export([all/0, init_per_testcase/2, end_per_testcase/2]).

-export([
  subscribe_unsubscribe_local/1,
  subscribe_unsubscribe_distributed/1,
  notify_lookup_local/1,
  notify_lookup_distributed/1,
  complex_test/1
]).

%% May it is not the best possible solution.
-define(SYNC_DELAY, 1000).

-define(TIMEOUT, 5000).
%milisconds
-define(WAIT_TIMEOUT, 5000).


-define(ACTION, #{
    subscribe_unsubscribe_distributed =>  #{
        
    },
    notify_lookup_distributed => #{
        
    },
    complex_test => #{
        
    }
 }).

-define(NODES, [
    'testnode1@host1.com',
    'testnode2@host2.com',
    'testnode3@host3.com'
]).


all() ->
    [
        subscribe_unsubscribe_local,
        subscribe_unsubscribe_distributed,
        notify_lookup_local,
        notify_lookup_distributed,
        complex_test
    ].



init_per_testcase(Case, Config) ->
    ct:pal("Started case ~p, node ~p, pid ~p, other nodes ~p", [Case, node(), self(), nodes()]),

    {ok, Pid} = esubscribe:start_link(),
    
    ProcRegName = list_to_atom("@test_" ++ atom_to_list(Case) ++ "@"),
    register(ProcRegName, self()),

    % in sync purposes %
    timer:sleep(?SYNC_DELAY),
    
    [{proc_reg_name, ProcRegName}, {esubscribe_pid, Pid} | Config].

end_per_testcase(Case, Config) ->
    ProcRegName = ?config(proc_reg_name, Config),
    sync_nodes('@esubscriptions_test_finsihed@', ProcRegName),
    EsubPid = ?config(esubscribe_pid, Config),
    exit(EsubPid, normal),
    ct:pal("Finished case ~p, node ~p", [Case, node()]),
    ok.

subscribe_unsubscribe_local(_Config) ->
    Master = self(),
    LocalSubscribe = fun(Term) -> 
        esubscribe:subscribe(Term, self()),
        receive
            {Master, '@end@'} -> ct:pal("ending procc")
        end
    end,
    Terms = [term1, term2, term3, term1, term2],
    LocalPIDs = [spawn(fun() -> LocalSubscribe(T) end) || T<- Terms],
    Term1 = hd(Terms),
    Pid1 = hd(LocalPIDs),
    esubscribe:subscribe(Term1, Pid1),
    esubscribe:subscribe(Term1, Pid1),

    ct:pal("Subscriptions ~p", [ets:match(?SUBSCRIPTIONS, '$1')]),

    UnsuscribebRouter = #{
        term1 => fun(_Term, Pid) ->Pid ! {Master, '@end@'} end,
        term2 => fun(Term, Pid) -> esubscribe:unsubscribe(Term, Pid) end,
        term3 => fun(_Term, Pid) -> exit(Pid, shutdown) end    
    },
    [begin
        Unsubscribe = maps:get(T, UnsuscribebRouter),
        Unsubscribe(T, PID)
    end || {T, PID} <-lists:zip(Terms, LocalPIDs)],

    %% That`s controversial moment, test does not work without it
    %% because ets table cannot delete object so fast (at least i think so)
    timer:sleep(1000),
    
    [] = ets:match(?SUBSCRIPTIONS, '$1'),
    ok.

subscribe_unsubscribe_distributed(Config) ->
    ProcRegName = ?config(proc_reg_name, Config),

    Master = self(),
    DistributedSubscribe = 
        fun() -> 
            receive
                {Master, '@end@'} -> ct:pal("end")
            end
        end,
    Terms = [term1, term2, term3, term4, term5, term1, term2],
    SubscribeNodes = [ 
        ['testnode1@host1.com', 'testnode2@host2.com', 'testnode3@host3.com'],
        ['testnode1@host1.com','testnode2@host2.com'],
        ['testnode2@host2.com', 'testnode3@host3.com'],
        ['testnode1@host1.com', 'testnode3@host3.com'],
        ['testnode1@host1.com'],
        ['testnode2@host2.com'],
        ['testnode3@host3.com']
    ],

    %% Subscribe on terms 
    LocalPIDs = [ begin
        Pid = spawn(fun() -> DistributedSubscribe() end), 
        esubscribe:subscribe(Term, Pid, Nodes),
        Pid
    end || {Term, Nodes}<- lists:zip(Terms, SubscribeNodes)],
    sync_nodes('@after_subscribe@', ProcRegName),
    
    
    UnsuscribeRouter = #{
        term1 => fun(Term, Pid, Nodes) -> esubscribe:unsubscribe(Term, Pid, Nodes) end,
        term2 => fun(_Term, Pid, _Nodes) -> Pid ! {Master, '@end@'} end,
        term3 => fun(_Term, Pid, _Nodes) -> exit(Pid, shutdown) end,
        term4 => fun(Term, Pid, Nodes) ->  esubscribe:unsubscribe(Term, Pid, Nodes) end,
        term5 => fun(Term, Pid, Nodes) ->  esubscribe:unsubscribe(Term, Pid, Nodes) end
    },
    %% Unsubscribe
    Res = [begin
        Unsubscribe = maps:get(Term, UnsuscribeRouter),
        Unsubscribe(Term, Pid, Nodes)
       end  || {Term, Pid, Nodes}<- lists:zip3(Terms, LocalPIDs, SubscribeNodes)],
    ct:pal("node ~p, Res ~p", [node(), Res]),
    
   
    sync_nodes('@after_unsubscribe@', ProcRegName),
    ct:pal("~p", [ets:match(?SUBSCRIPTIONS, '$1')]) ,


    %% That`s controversial moment, test does not work without it
    %% because ets table cannot delete object so fast (at least i think so)
    % timer:sleep(1000),
    [] = ets:match(?SUBSCRIPTIONS, '$1'),
    ok.

notify_lookup_local(_Config) ->
    Master = self(),
    LocalLookUp = fun(Term) ->
        receive 
            {Master, '@ready@'} -> ct:pal("Received")
        end,
        Result = esubscribe:lookup(Term),
        ct:pal("LookUp Result ~p", [Result]),
        Master ! {'@result@', self(), Term, Result}   
    end,
    LocalWait = fun(Term) ->
        Result = esubscribe:wait(Term, ?WAIT_TIMEOUT),
        ct:pal("Wait Result ~p", [Result]),
        Master ! {'@result@',self(), Term, Result}   
    end,

    Terms = [term1, term2, term3, term1, term2],
    LocalPIDs = 
        [begin
            Pid = 
                if Idx rem 2 == 1 -> spawn(fun() -> LocalLookUp(Term) end);
                    true -> spawn(fun() -> LocalWait(Term) end)
                end,
            esubscribe:subscribe(Term, Pid),
            Pid
        end || {Idx, Term}<- lists:zip( lists:seq(1, length(Terms)), Terms)],

    % timer:sleep(1000),
    ct:pal("table ~p", [ets:match(?SUBSCRIPTIONS, '$1')]),

    [esubscribe:notify(Term, Term) ||Term <- Terms],  
    % timer:sleep(1000),

    [begin  
        if Idx rem 2 == 1 -> Pid ! {Master, '@ready@'};
            true -> ok
        end
    end|| {Idx, Pid} <- lists:zip( lists:seq(1, length(LocalPIDs)), LocalPIDs)],

    TermNotifications = lists:foldl(fun(Term, Acc) -> 
        Notification = maps:get(Term, Acc, []), 
        Notification1 = [{Term, node(), Master} | Notification],
        Acc#{Term => Notification1}
    end, #{}, Terms),

    [begin
        receive
            {'@result@', _ChildPid, Term, Result} -> 
                Expected = maps:get(Term, TermNotifications),
                ct:pal("Term ~p, Result ~p", [Term, Result]),
                Expected = Result
        after 10000 -> ct:pal("Timeout")

        end
     end|| _Pid<- LocalPIDs],

    ok.

notify_lookup_distributed(Config) ->
    ProcRegName = ?config(proc_reg_name, Config),

    Terms = [term, term1, term2, term3],
    SubscribeNodes = [ 
        ['testnode1@host1.com', 'testnode2@host2.com', 'testnode3@host3.com'],
        ['testnode1@host1.com'],
        ['testnode2@host2.com'],
        ['testnode3@host3.com']
    ],
    Indexes = lists:seq(1, length(Terms)),

    Master = self(),
    LookUp = fun(Term) ->
        receive 
            {Master, '@ready@'} -> ct:pal("Received")
        end,
        Result = esubscribe:lookup(Term),
        ct:pal("LookUp result ~p", [Result]),
        Master ! {'@result@', self(), Term, Result}
    end,
    Wait = fun(Term) ->
        Result = esubscribe:wait(Term, ?WAIT_TIMEOUT),
        Master ! {'@result@', self(), Term, Result}
        end,
    
    LocalPIDs = 
        [begin
            Pid = 
                if Idx == 1 ->
                    spawn(fun() -> LookUp(Term) end);
                    true -> spawn(fun() -> Wait(Term) end)
                end,
            esubscribe:subscribe(Term, Pid, Nodes),
            Pid
        end || {Idx, Term, Nodes} <- lists:zip3(Indexes, Terms, SubscribeNodes)],

    sync_nodes('@after_subscribe@', ProcRegName),

    [esubscribe:notify(Term, Term) || Term<-Terms],

    sync_nodes('@after_notify@', ProcRegName),

    Pid1 = hd(LocalPIDs),
    Pid1 ! {Master, '@ready@'},
    receive 
        {'@result@', _ChildPid, term, DistributedResult} ->
            DistributedResult1 = lists:sort(DistributedResult),
            [{term, 'testnode1@host1.com', _}, {term, 'testnode2@host2.com', _}, {term, 'testnode3@host3.com', _}] = DistributedResult1
    end,
    

    ok.

complex_test(_Config) ->
    % Fun = get_function(complex_test),
    % Fun(),
    ok.

%%=================================================================
%% Utilities
%%=================================================================
sync_nodes(Msg, ProcRegName) ->
    Nodes = ?NODES -- [node()],
    [{ProcRegName, N} ! Msg|| N<-Nodes],
    do_sync_nodes(Msg, length(Nodes)).

do_sync_nodes(Msg, N) when N>0->
    receive
        Msg -> do_sync_nodes(Msg, N - 1)
    end;
do_sync_nodes(_Msg, 0) ->
    ok.

per_case_debug(Case) -> 
    Debug = ct:get_config(debug_print),
    if 
        Debug -> ct:pal("Node ~p. Test_case ~p. Other nodes ~p", [node(), Case, nodes()]);
        true -> ok
    end,
    ok.   

get_function(Case) -> 
    maps:get(node(),  maps:get(Case, ?ACTION)).