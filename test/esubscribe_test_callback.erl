-module(esubscribe_test_callback).



-export([start/3]).


%% This module is not necessary, here we just do some simple transformations
start(Host, Node, Options) ->
    io:format("Host ~p, Node ~p, Options ~p Dir ~p~n", [Host, Node, Options, os:cmd("pwd")]),
    Node1 = list_to_atom( atom_to_list(Node) ++ "@" ++ atom_to_list(Host)),
    io:format("Node1 ~p~n", [Node1]),
    ct_slave:start(Host, Node1, Options).