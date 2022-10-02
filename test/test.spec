{define, 'MODULE_TEST', "./"}.
{define, 'ERL_FLAGS', "-pa ../../_build/default/lib/esubscribe/ebin ../../_build/default/lib/ecall/ebin ../../_build/default/lib/lager/ebin ../../_build/default/lib/goldrush/ebin"}.

{node, node1, 'testnode1@host1.com'}.
{node, node2, 'testnode2@host2.com'}.
{node, node3, 'testnode3@host3.com'}.

%% callback_module is dirty hack, it does not any useful work
%% but it won`t work without it
{init, [node1, node2, node3], [{node_start, [
    {callback_module, esubscribe_test_callback}, 
    {boot_timeout, 5}, 
    {monitor_master, true}, 
    {username, "levi"}, 
    {password, "123"},
    {erl_flags, 'ERL_FLAGS'}
    ]
 }]}.
{include, "../include/"}.
{config, all_nodes, "node.cfg"}.


{logdir, master, "../distributed_logs/"}.
{logdir, all_nodes, "../distributed_logs/"}.

{suites, [node1, node2, node3], 'MODULE_TEST', [
    esubscribe_SUITE
]}.