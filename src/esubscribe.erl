
-module(esubscribe).

%%=================================================================
%% OTP
%%=================================================================
-export([
  start_link/0
]).
%%=================================================================
%% API
%%=================================================================
-export([
  subscribe/2, subscribe/3,
  unsubscribe/2, unsubscribe/3,
  notify/2,
  lookup/1,
  wait/2
]).
%%=================================================================
%% This functions is exported only for test
%%=================================================================

-define(SUBSCRIPTIONS,'$esubscriptions').

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
  case whereis( ?MODULE ) of
    PID when is_pid( PID )->
      {error, {already_started, PID}};
    _ ->
      {ok, spawn_link(fun()-> init() end)}
  end.

init()->

  register(?MODULE, self()),

  % Prepare the storage for locks
  ets:new(?SUBSCRIPTIONS,[named_table,public,bag]),

  timer:sleep(infinity).


%%=================================================================
%%	Subscriptions API
%%=================================================================
subscribe(Term, PID)->
  Clients = ets:lookup(?SUBSCRIPTIONS, Term),
  case [registered || {_,C,_} <- Clients, C=:= PID] of
    []->
      spawn(fun()->
        ets:insert(?SUBSCRIPTIONS,{ Term, PID, self() }),
        ?LOGDEBUG("~p subscribed on ~p",[PID, Term]),
        guard( monitor(process, PID), Term, PID  )
      end);
    _->
      % Already registered
      ignore
  end,
  ok.

guard( Ref, Term, PID )->
  receive
    unsubscribe->
      ?LOGDEBUG("~p unsubscribed from ~p",[PID,Term]),
      ets:delete_object( ?SUBSCRIPTIONS, {Term, PID, self()} );
    {'DOWN', Ref, _Type, _Object, _Info}->
      ?LOGDEBUG("~p down unsubscribe from ~p",[PID,Term]),
      ets:delete_object( ?SUBSCRIPTIONS, {Term, PID, self()} );
    _->
      guard( Ref, Term, PID )
  end.

subscribe(Term, PID, Nodes)->
  ecall:call_all_wait(Nodes,?MODULE,?FUNCTION_NAME,[Term,PID]).

unsubscribe( Term, PID )->
  [ G ! unsubscribe || {_,C,G} <- ets:lookup(?SUBSCRIPTIONS, Term), C=:=PID ],
  ok.

unsubscribe( Term, PID, Nodes )->
  ecall:call_all_wait(Nodes,?MODULE,?FUNCTION_NAME,[Term,PID]).

notify( Term, Action )->
  try case ets:lookup(?SUBSCRIPTIONS, Term) of
    [] ->
      ok;
    Clients->
      Node = node(), Self = self(),
      [ C ! {'$esubscription', Term, Action, Node, Self} || {_,C,_} <- Clients ],
      ok
  end catch
    _:_-> {error, not_available}
  end.

lookup( Term )->
  receive
    {'$esubscription', Term, Action, Node, Actor}->
      [{Action,Node,Actor} | lookup( Term ) ]
  after
    0->[]
  end.

wait( Term, infinity ) ->
  receive
    {'$esubscription', Term, Action, Node, Actor}->
      [{Action,Node,Actor} | wait( Term, infinity ) ]
  end;

wait( Term, Timeout ) when Timeout >0 ->
  TS0 = erlang:system_time(millisecond),
  receive
    {'$esubscription', Term, Action, Node, Actor}->
      [{Action,Node,Actor} | wait( Term, Timeout-(erlang:system_time(millisecond) -TS0 )) ]
  after
    Timeout->[]
  end.

