-module(esubscribe_local_SUITE).

-include_lib("esubscribe.hrl").
-include_lib("esubscribe_test.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
 ]).

-export([
    where_to_subscribe_test/1,
    do_subscribe_test/1,
    add_subscription_test/1,
    remove_subscription_test/1
 ]).

all() ->
    [
        where_to_subscribe_test,
        do_subscribe_test,
        add_subscription_test,
        remove_subscription_test
    ].


init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

where_to_subscribe_test(_Config) ->
    Pid1 = c:pid(0,1,1), Pid2 = c:pid(0,1,2), Pid3 = c:pid(0,1,3), Pid4 = c:pid(0,1,4), Pid5 = c:pid(0,1,5),
    Node1 = 'node1@127.0.0.1', Node2 = 'node2@127.0.0.1', Node3 = 'node3@127.0.0.1',
    Subs = #{
        Pid1 => #{term1 => [Node1, Node2, Node3], term2 => [Node1, Node3], term3 => [Node2]},
        Pid2 => #{term1 => [Node1], term3 => [Node3, Node2]},
        Pid3 => #{ 1 => [Node1], 2 => [Node2], 3 => [Node3] },
        Pid5 => #{ {1,2} => [Node3, Node2, Node1]}
    },
    [] = esubscribe:where_to_subscribe(Pid1, term1, [Node1, Node2], Subs),
    [Node2] = esubscribe:where_to_subscribe(Pid1, term2, [Node1, Node2], Subs),
    [Node3, Node1] = esubscribe:where_to_subscribe(Pid1, term3, [Node3, Node1], Subs),
    [Node1, Node2, Node3] = esubscribe:where_to_subscribe(Pid1, term4, [Node1, Node2, Node3], Subs),

    [Node1, Node2] = esubscribe:where_to_subscribe(Pid4, {1,2}, [Node1, Node2], Subs),
    ok.

do_subscribe_test(_Config) ->
    ets:new(?SUBSCRIPTIONS, [named_table, protected, {keypos, #sub.term}]),

    Pid1 = c:pid(0,1,1), Pid2 = c:pid(0, 1, 2), _Pid3 = c:pid(0, 1, 3),
    CurrentNode = node(),
        
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid1, term1, [CurrentNode]),
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid1, term2, [CurrentNode]),
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid1, term3, [CurrentNode]),
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid1, term1, [CurrentNode]),

    {[CurrentNode], []} = esubscribe:do_subscribe(Pid2, term1, [CurrentNode]),
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid2, term2, [CurrentNode]),
    {[CurrentNode], []} = esubscribe:do_subscribe(Pid2, term2, [CurrentNode]),

    [#sub{clients = [Pid1, Pid2]}] = ets:lookup(?SUBSCRIPTIONS, term1),
    [#sub{clients = [Pid1, Pid2]}] = ets:lookup(?SUBSCRIPTIONS, term2),
    [#sub{clients = [Pid1]}] = ets:lookup(?SUBSCRIPTIONS, term3),
    [] = ets:lookup(?SUBSCRIPTIONS, term4),
    ets:delete(?SUBSCRIPTIONS),
    ok.

add_subscription_test(_Config) ->
    Pid1 = c:pid(0, 1, 1), Pid2 = c:pid(0, 1, 2), Pid3 = c:pid(0, 1, 3),
    Node1 = 'node1@127.0.0.1', Node2 = 'node2@127.0.0.1', Node3 = 'node3@127.0.0.1',
    Subs = #{
        Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
        Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]}
    },
    ?assertEqual(#{
            Pid1 => #{term1 => [Node2, Node3, Node1], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]}
        }, 
        esubscribe:add_subscription(Pid1, term1, [Node1], Subs)
    ),
    ?assertEqual(#{
            Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]}
        },
        esubscribe:add_subscription(Pid1, term1, [Node3], Subs)
    ),
    ?assertEqual(#{
            Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3], term1 => [Node1,Node2]}
        },
        esubscribe:add_subscription(Pid2, term1, [Node1, Node2], Subs)
    ),
    ?assertEqual(#{
            Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
            Pid3 => #{term3 => [Node1, Node3]}
        },
        esubscribe:add_subscription(Pid3, term3, [Node1, Node3], Subs)
    ),
    ok.

remove_subscription_test(_Config) ->
    Pid1 = c:pid(0, 1, 1), Pid2 = c:pid(0, 1, 2), Pid3 = c:pid(0, 1, 3), Pid4 = c:pid(0, 1, 4), 
    Node1 = 'node1@127.0.0.1', Node2 = 'node2@127.0.0.1', Node3 = 'node3@127.0.0.1',
    Subs = #{
        Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
        Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
        Pid3 => #{term3 => [Node1, Node2, Node3]}
    },
    ?assertEqual(#{
            Pid1 => #{term1 => [Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
            Pid3 => #{term3 => [Node1, Node2, Node3]}
        },
        esubscribe:remove_subscription(Pid1, term1, [Node1, Node2], Subs)
    ),
    ?assertEqual(#{
            Pid1 => #{term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
            Pid3 => #{term3 => [Node1, Node2, Node3]}
        },
        esubscribe:remove_subscription(Pid1, term1, [Node1, Node2, Node3], Subs)
    ),
    ?assertEqual(#{
            Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
            Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]}
        },
        esubscribe:remove_subscription(Pid3, term3, [Node1, Node2, Node3], Subs)
    ),
    ?assertEqual(#{
        Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
        Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
        Pid3 => #{term3 => [Node1, Node2, Node3]}
    },
        esubscribe:remove_subscription(Pid2, term1, [Node1, Node2, Node3], Subs)
    ),
    ?assertEqual(#{
        Pid1 => #{term1 => [Node2, Node3], term2 => [Node1, Node3], term3 => [Node2, Node3]},
        Pid2 => #{term2 => [Node3], term4 => [Node2, Node3]},
        Pid3 => #{term3 => [Node1, Node2, Node3]}
    },
        esubscribe:remove_subscription(Pid4, term1, [Node1, Node2, Node3], Subs)
    ),
    ok.