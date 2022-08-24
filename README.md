# elock
Erlang library for distributed term subscriptions.

I tried to keep API as simple as possible.

I appreciate any pull requests for bug fixing, tests or extending the functionality.

API
-----

    esubscribe:start_link()
    
    Call it from an OTP supervisor as a permanent worker. Example:
    
    MySubsriptionsServer = #{
        id=>esubscribe,
        start=>{esubscribe,start_link,[]},
        restart=>permanent,
        shutdown=> <It's up to you>
        type=>worker,
        modules=>[esubscribe]
    },
    
    Ok now you are ready for subscriptions. If you need distributed subscriptions do the same
    at your other nodes.
    
    If you want to subscribe on any erlang term call:
    
    {YesNodes,NoNodes} | {error, timeout} | {error, not_available} =  esubscribe:subscribe(Term, Nodes, PID, Timeout)

    Term is any erlang term
    Nodes is a list of nodes where you want subscribe
    PID is self() ??? Why I need to pass my PID take it as self(). Yes you can subscribe another process
    Timeout is Milliseconds or infinity
    
    [Node1,Node2|_AndSoOn] = YesNodes are the nodes from Nodes where you were susccessful
    
    [{Node1,Reason1},{Node2,Reason2}|_AndSoOn] = NoNodes are the nodes where you failed with reasons
    
    If you want to notify on any term call:
    
    ok | {error, not_available} = esubscribe:notify( Term, Action )
    
    Term is any erlang term
    Action is also any erlang term
    
    
    
    
    
    Others are more interesting:

    set IsShared = true if it is enough for you to be sure that the term is locked may be
    even not by you. 
    
    Nodes is where else you want to lock the Term. If the Nodes is [] the Term
    will be locked only locally

    When you need to unlock the Term call Unlock() from returned to you {ok,Unlock}.

    Avoid setting lock on the term you'v already locked, you will get a deadlock.

    that's it.
    
    
    
BUILD
-----
    Add it as a dependency to your application and you are ready (I use rebar3)
    {deps, [
        ......
        {elock, {git, "git@github.com:vzroman/elock.git", {branch, "main"}}}
    ]}.

TODO
-----
    Tests!!!
    