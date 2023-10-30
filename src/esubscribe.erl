
-module(esubscribe).

%%=================================================================
%% OTP
%%=================================================================
-export([
  start_link/0, start_link/1
]).
%%=================================================================
%% API
%%=================================================================
-export([
  subscribe/2, subscribe/3, subscribe/4,
  unsubscribe/2, unsubscribe/3, unsubscribe/4,
  notify/2,notify/3,
  lookup/1, lookup/2,
  wait/2, wait/3
]).
%%=================================================================
%% This functions is exported only for test
%%=================================================================
-define(GLOBAL_SCOPE,'$esusbcription$').
-define(PID_NAME(Scope),list_to_atom( atom_to_list(Scope)++"_server")).

-define(LOGERROR(Text),lager:error(Text)).
-define(LOGERROR(Text,Params),lager:error(Text,Params)).
-define(LOGWARNING(Text),lager:warning(Text)).
-define(LOGWARNING(Text,Params),lager:warning(Text,Params)).
-define(LOGINFO(Text),lager:info(Text)).
-define(LOGINFO(Text,Params),lager:info(Text,Params)).
-define(LOGDEBUG(Text),lager:debug(Text)).
-define(LOGDEBUG(Text,Params),lager:debug(Text,Params)).

%%=================================================================
%% Service API
%%=================================================================
start_link() ->
  start_link( ?GLOBAL_SCOPE ).

start_link( Scope ) ->
  case whereis( ?PID_NAME(Scope) ) of
    PID when is_pid( PID )->
      {error, {already_started, PID}};
    _ ->
      {ok, spawn_link(fun()-> init( Scope ) end)}
  end.

init( Scope )->

  register(?PID_NAME(Scope), self()),

  % Prepare the storage for locks
  ets:new(Scope,[
    named_table,
    public,bag,
    {read_concurrency, true},
    {write_concurrency, auto}
  ]),

  timer:sleep(infinity).


%%=================================================================
%%	Subscriptions API
%%=================================================================
subscribe(Term, PID)->
  subscribe(?GLOBAL_SCOPE, Term, PID).
subscribe(Scope, Term, PID) when is_pid(PID)->
  Clients = ets:lookup(Scope, Term),
  case [registered || {_,C,_} <- Clients, C=:= PID] of
    []->
      spawn(fun()->
        ets:insert(Scope,{ Term, PID, self() }),
        ?LOGDEBUG("~p subscribed on ~p",[PID, Term]),
        guard( monitor(process, PID), Scope, Term, PID  )
      end);
    _->
      % Already registered
      ignore
  end,
  ok;
subscribe(Term, PID, Nodes) when is_list( Nodes )->
  subscribe(?GLOBAL_SCOPE, Term, PID, Nodes ).
subscribe(Scope, Term, PID, Nodes) when is_list( Nodes )->
  ecall:call_all_wait(Nodes,?MODULE,?FUNCTION_NAME,[Scope,Term,PID]).

guard( Ref, Scope, Term, PID )->
  receive
    unsubscribe->
      ?LOGDEBUG("~p unsubscribed from ~p",[PID,Term]),
      catch ets:delete_object( Scope, {Term, PID, self()} );
    {'DOWN', Ref, _Type, _Object, _Info}->
      ?LOGDEBUG("~p down unsubscribe from ~p",[PID,Term]),
      catch ets:delete_object( Scope, {Term, PID, self()} );
    _->
      guard( Ref, Scope,Term, PID )
  end.

unsubscribe( Term, PID )->
  unsubscribe( ?GLOBAL_SCOPE, Term, PID ).
unsubscribe(Scope, Term, PID ) when is_pid(PID)->
  [ G ! unsubscribe || {_,C,G} <- ets:lookup(Scope, Term), C=:=PID ],
  ok;
unsubscribe( Term, PID, Nodes ) when is_list(Nodes)->
  unsubscribe(?GLOBAL_SCOPE, Term, PID, Nodes).
unsubscribe(Scope, Term, PID, Nodes ) when is_list(Nodes)->
  ecall:call_all_wait(Nodes,?MODULE,?FUNCTION_NAME,[Scope,Term,PID]).

notify( Term, Action )->
  notify(?GLOBAL_SCOPE, Term, Action).
notify(Scope, Term, Action )->
  try case ets:lookup(Scope, Term) of
    [] ->
      ok;
    Clients->
      Node = node(), Self = self(),
      [ ecall:send(C, {Scope, Term, Action, Node, Self} ) || {_,C,_} <- Clients ],
      ok
  end catch
    _:_-> {error, not_available}
  end.

lookup( Term )->
  lookup(?GLOBAL_SCOPE, Term ).
lookup(Scope, Term)->
  receive
    {Scope, Term, Action, Node, Actor}->
      [{Action,Node,Actor} | lookup(Scope, Term ) ]
  after
    0->[]
  end.

wait( Term, Timeout ) ->
  wait(?GLOBAL_SCOPE, Term, Timeout).
wait(Scope, Term, infinity ) ->
  receive
    {Scope, Term, Action, Node, Actor}->
      [{Action,Node,Actor} | wait(Scope, Term, infinity ) ]
  end;

wait(Scope, Term, Timeout ) when Timeout >0 ->
  TS0 = erlang:system_time(millisecond),
  receive
    {Scope, Term, Action, Node, Actor}->
      [{Action,Node,Actor} | wait(Scope, Term, Timeout-(erlang:system_time(millisecond) -TS0 )) ]
  after
    Timeout->[]
  end.

