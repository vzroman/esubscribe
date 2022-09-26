
-module(esubscribe).

-include_lib("esubscribe.hrl").
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
  subscribe/4,
  unsubscribe/3,
  notify/2,
  lookup/1,
  wait/2
]).
%%=================================================================
%% This functions is exported only for test
%%=================================================================
-ifdef(TEST).
-export([
  where_to_subscribe/4,
  do_subscribe/3,
  add_subscription/4,
  remove_subscription/4
]).
-endif.


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
      Sup = self(),
      {ok, spawn_link(fun()-> init(Sup) end)}
  end.

init( Sup )->

  register(?MODULE, self()),

  % Prepare the storage for subscriptions
  ets:new(?SUBSCRIPTIONS,[named_table,protected,set,{keypos, #sub.term}]),

  process_flag(trap_exit,true),

  ?LOGINFO("start subscriptions server pid ~p",[ self() ]),

  wait_loop(Sup, _Subs = #{ }).


%%=================================================================
%%	Subscriptions API
%%=================================================================

subscribe(Term, Nodes, PID, Timeout)->
  case whereis( ?MODULE ) of
    Server when is_pid( Server )->
      Server ! {subscribe, Term, Nodes, _ReplyTo = self() , PID},
      receive
        {Server,YesNodes,NoNodes} -> {YesNodes,NoNodes}
      after
        Timeout->
          Server ! {unsubscribe, Term, Nodes, PID},
          receive
            {Server,_YesNodes,_NoNodes} ->
              ignore
          after
            10-> ignore
          end,
          {error, timeout}
      end;
    _->
      {error, not_available}
  end.

unsubscribe( Term, Nodes, PID )->
  case whereis( ?MODULE ) of
    Server when is_pid( Server )->
      Server ! {unsubscribe, Term, Nodes, PID},
      ok;
    _->
      {error, not_available}
  end.

notify( Term, Action )->
  try case ets:lookup(?SUBSCRIPTIONS, Term) of
    [] ->
      ok;
    [#sub{ clients = Clients }]->
      Node = node(), Self = self(),
      [ C ! {'$esubscription', Term, Action, Node, Self} || C <- Clients ],
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

%%---------------------------------------------------------------------
%%  Server loop
%%---------------------------------------------------------------------
wait_loop(Sup, Subs)->
  receive
    {subscribe, Term, Nodes, ReplyTo, PID}->
      AddNodes = where_to_subscribe( PID, Term, Nodes, Subs ),
      {YesNodes,NoNodes} = do_subscribe(PID, Term, AddNodes),
      ReplyTo ! {self(),YesNodes,NoNodes},
      NewSubs = add_subscription( PID, Term, YesNodes, Subs ),

      ?LOGDEBUG("~p subscribed on ~p at nodes ~p, rejected at ~p",[PID,Term,YesNodes,NoNodes]),
      wait_loop( Sup, NewSubs );

    {unsubscribe, Term, Nodes, PID}->
      ?LOGDEBUG("~p unsubscribed from ~p at ~p",[PID,Term,Nodes]),
      do_unsubscribe( PID, Term, Nodes ),
      NewSubs = remove_subscription( PID, Term, Nodes, Subs ),
      wait_loop( Sup, NewSubs );

    {'EXIT',PID, Reason} when PID =/= Sup->
      case Subs of
        #{ PID := Terms }->
          ?LOGDEBUG("~p subcriber died, reason ~p, remove subscriptions ~p",[ PID, Reason, Terms ]),
          do_unsubscribe( PID, maps:keys( Terms )),
          wait_loop(Sup, maps:remove( PID, Subs ));
        _->
          % Who was it?
          wait_loop(Sup, Subs)
      end;
    {'EXIT',Sup, Reason} when Reason =:= normal; Reason=:=shutdown->
      ?LOGINFO("stop subcriptions server, reason ~p",[ Reason]);
    {'EXIT',Sup, Reason}->
      ?LOGERROR("subcriptions server exit, reason ~p",[ Reason ]);
    Unexpected->
      ?LOGDEBUG("subcriptions server got unexpected message ~p",[Unexpected]),
      wait_loop( Sup, Subs )
  end.

where_to_subscribe( PID, Term, Nodes, Subs )->
  case Subs of
    #{ PID := Terms }->
      case Terms of
        #{Term := AlreadyNodes}->
          Nodes -- AlreadyNodes;
        _->
          Nodes

      end;
    _->
      % A new client
      case lists:member(node(),Nodes) of
        true ->
          % Mine
          link(PID);
        _->
          not_mine
      end,
      Nodes
  end.

do_subscribe(PID, Term, Nodes)->
  OtherNodes = Nodes -- [node()],
  IsMine = length(OtherNodes) =/= length(Nodes),
  if
    IsMine->
      case ets:lookup(?SUBSCRIPTIONS,Term) of
        [#sub{clients = Clients}=S] ->
          true = ets:insert(?SUBSCRIPTIONS,S#sub{ clients = (Clients -- [PID]) ++ [PID] });
        []->
          true = ets:insert(?SUBSCRIPTIONS,#sub{term = Term,clients = [PID]})
      end;
    true->
      not_mine
  end,
  {YesNodes,NoNodes}=
    if
      length(OtherNodes)>0->
        Results = [{N, rpc:call(N, ?MODULE, subscribe, [Term,[N],PID,_Timeout = infinity]) } || N <- OtherNodes ],
        _YesNodes = [N || {N,{[N],[]}} <- Results ],
        _NoNodes = [{N,Reason} || {N,{Error,Reason}} <- Results, (Error =:= badrpc) or (Error =:= error) ],
        {_YesNodes,_NoNodes};
      true->
        {[],[]}
    end,
  if
    IsMine->
      {[node()|YesNodes], NoNodes};
    true->
      {YesNodes,NoNodes}
  end.

add_subscription( PID, Term, AddNodes, Subs )->
  case Subs of
    #{ PID:=Terms }->
      case Terms of
        #{Term:=Nodes}->
          Subs#{ PID => Terms#{ Term=> (Nodes -- AddNodes) ++ AddNodes } };
        _->
          Subs#{ PID=>Terms#{ Term => AddNodes }}
      end;
    _->
      Subs#{ PID=>#{ Term => AddNodes }}
  end.

do_unsubscribe(PID, Term, Nodes)->
  OtherNodes = Nodes -- [node()],
  IsMine = length(OtherNodes) =/= length(Nodes),
  if
    IsMine->
      case ets:lookup(?SUBSCRIPTIONS, Term) of
        [#sub{clients = Clients}=S] ->
          case Clients -- [PID] of
            []-> ets:delete(?SUBSCRIPTIONS, Term );
            RestClients -> ets:insert(?SUBSCRIPTIONS, S#sub{ clients = RestClients })
          end;
        []->
          ignore
      end;
    true->
      ignore
  end,

  if
    length(OtherNodes)>0->
      [ rpc:cast(N, ?MODULE, unsubscribe, [Term,[N],PID]) || N <- OtherNodes ],
      ok;
    true->
     ok
  end.

do_unsubscribe(PID, [Term|Rest])->
  % Died, no need to cast other nodes, they will receive the same trap
  case ets:lookup(?SUBSCRIPTIONS, Term) of
    [#sub{clients = Clients}=S] ->
      case Clients -- [PID] of
        []-> ets:delete(?SUBSCRIPTIONS, Term );
        RestClients ->
          ets:insert(?SUBSCRIPTIONS, S#sub{ clients = RestClients })
      end;
    []->
      ignore
  end,
  do_unsubscribe(PID, Rest);
do_unsubscribe(_PID, [])->
  ok.


remove_subscription( PID, Term, RemoveNodes, Subs )->
  case Subs of
    #{ PID:= Terms }->
      case Terms of
        #{ Term:=Nodes }->
          case Nodes -- RemoveNodes of
            []->
              RestTerms = maps:remove(Term, Terms),
              case maps:size( RestTerms ) of
                0->
                  % Not a client from now
                  unlink(PID),
                  maps:remove(PID,Subs);
                _->
                  Subs#{ PID => RestTerms }
              end;
            RestNodes->
              Subs#{ PID=>Terms#{ Term => RestNodes }}
          end;
        _->
          Subs
      end;
    _->
      % Who was it?
      unlink( PID ),
      Subs
  end.
