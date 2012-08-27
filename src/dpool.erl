-module(dpool).
-behaviour(gen_server).
-record(state, {slaves=[], subscribers=[], workers=[], q=[]}).
-record(slave, {node, capacity=2, load=0}).
-record(worker, {node, f, pid}).
-export([
	init/1,
	handle_call/3, handle_cast/2, handle_info/2,
	terminate/2, code_change/3,
	start_link/0
]).


% core functionality
calc_capacity(Node) -> rpc:call(Node, erlang, system_info, [schedulers])+1.


get_capacity(S) ->
	lists:sum([Slave#slave.capacity || Slave <- S#state.slaves]).

get_load(S) ->
	lists:sum([Slave#slave.load || Slave <- S#state.slaves]).

get_q(S) -> length(S#state.q).


attach(Node, Capacity, S=#state{slaves=Slaves}) ->
	case lists:keymember(Node, 2, Slaves) of
		true -> {already_attached, S};
		false ->
			monitor_node(Node, true),
			{ok, S#state{slaves=[#slave{node=Node, capacity=Capacity} | Slaves]}}
	end.

detach(Node, S) ->
	case lists:keytake(Node, 2, S#state.slaves) of
		false -> {not_attached, S};
		{value, _Slave, Slaves} ->
			monitor_node(Node, false),
			{ok, S#state{slaves=Slaves}}
	end.


subscribe(Pid, S=#state{subscribers=Subs}) ->
	case lists:member(Pid, Subs) of
		true -> {already_subscribed, S};
		false -> {ok, S#state{subscribers=[Pid | Subs]}}
	end.

unsubscribe(Pid, S=#state{subscribers=Subs}) ->
	case lists:member(Pid, Subs) of
		false -> {not_subscribed, S};
		true -> {ok, S#state{subscribers=lists:delete(Pid, Subs)}}
	end.


notify(S, state) ->
	log:log("dpool: load: ~p/~p (~p)~n", [get_load(S), get_capacity(S), get_q(S)]),
	do_notify(S, {dpool_state, get_load(S), get_capacity(S), get_q(S)}).


notify(S, worker, W) ->
	do_notify(S, {dpool_worker, W}).


do_notify(#state{subscribers=Subs}, Msg) -> [Sub ! Msg || Sub <- Subs], ok.


get_nodes_capacity(#state{slaves=Slaves}) ->
	lists:keysort(2, lists:map(fun(Slave) ->
		{Slave#slave.node, Slave#slave.capacity-Slave#slave.load}
	end, Slaves)).

choose_node(S) ->
	case get_nodes_capacity(S) of
		[] -> no_workers;
		[{Node, _} | _] -> Node
	end.


start_worker(F, S) ->
	log:log("dpool: trying to start worker ~p~n", [F]),
	case choose_node(S) of
		no_workers -> {queued, S#state{q=S#state.q++[F]}};
		Node -> start_worker(Node, F, S)
	end.

start_worker(Node, F, S = #state{slaves=Slaves}) ->
	log:log("dpool: starting worker ~p on node ~p~n", [F, Node]),
	case lists:keyfind(Node, 2, Slaves) of
		false -> {not_attached, S};
		Slave ->
			Pid = spawn_link(Node, F),
			NewSlave = Slave#slave{load=Slave#slave.load+1},
			Worker = #worker{node=Node, f=F, pid=Pid},
			{Worker, S#state{
				workers=[Worker | S#state.workers],
				slaves=lists:keyreplace(Node, 2, Slaves, NewSlave)
			}}
	end.

remove_worker(Pid, S=#state{slaves=Slaves}) ->
	case lists:keytake(Pid, 4, S#state.workers) of
		false -> {not_running, S};
		{value, Worker, Workers} ->
			NewSlaves = case lists:keytake(Worker#worker.node, 2, Slaves) of
				false -> Slaves;
				{value, Slave, Slaves1} ->
					NewSlave = Slave#slave{load=Slave#slave.load-1},
					[NewSlave | Slaves1]
			end,
			{Worker, S#state{workers=Workers, slaves=NewSlaves}}
	end.

restart_worker(Pid, S) ->
	case remove_worker(Pid, S) of
		A = {not_running, _} -> A;
		{W, NS} -> start_worker(W#worker.f, NS)
	end.

start_worker_from_q(S) ->
	case S#state.q of
		[] -> {empty_q, S};
		[Worker | Queue] ->
			case get_load(S) >= get_capacity(S) of
				true -> {out_of_capacity, S};
				false ->
					{Pid, S1} = start_worker(Worker, S),
					{Pid, S1#state{q=Queue}}
			end
	end.

handle_worker_exit(Pid, S) ->
	{_, S1} = remove_worker(Pid, S),
	start_worker_from_q(S1).

% callbacks
init(_Args) ->
	process_flag(trap_exit, true),
	{ok, #state{}}.


handle_call(capacity, _From, S) -> {reply, get_capacity(S), S};

handle_call(load, _From, S) -> {reply, get_load(S), S};

handle_call(q, _From, S) -> {reply, get_q(S), S};


handle_call({attach, Node}, From, S) ->
	handle_call({attach, Node, calc_capacity(Node)}, From, S);

handle_call({attach, Node, Capacity}, _From, S) ->
	{Reply, S1} = attach(Node, Capacity, S),
	{W, S2} = start_worker_from_q(S1),
	notify(S2, state),
	case W of
		empty_q -> ok;
		out_of_capacity -> ok;
		_ -> notify(S2, worker, W)
	end,
	{reply, Reply, S2};


handle_call({detach, Node}, _From, S) ->
	{Reply, NS} = detach(Node, S),
	notify(NS, state),
	{reply, Reply, NS};


handle_call(subscribe, {Pid, _Ref}, S) ->
	%TODO: DRY f(label, tuple) -> {label, tuple...}
	{Reply, NS} = subscribe(Pid, S),
	{reply, Reply, NS};

handle_call(unsubscribe, {Pid, _Ref}, S) ->
	{Reply, NS} = unsubscribe(Pid, S),
	{reply, Reply, NS};


handle_call({start, F}, _From, S) ->
	{W, NS} = start_worker(F, S),
	notify(NS, state),
	case W of
		queued -> ok;
		_ -> notify(NS, worker, W)
	end,
	{reply, W, NS}.

handle_cast(Req, S) ->
	log:log("dpool: unexpected cast: ~p~n", [Req]),
	{noreply, S}.


handle_info({nodedown, Node}, S) ->
	log:log("dpool: node ~p down~n", [Node]),
	{_, NS} = detach(Node, S),
	notify(NS, state),
	{noreply, NS};


handle_info({'EXIT', Pid, normal}, S) ->
	log:log("dpool: worker ~p has exited normally~n", [Pid]),
	{W, S1} = handle_worker_exit(Pid, S),
	notify(S1, state),
	case W of
		empty_q -> ok;
		out_of_capacity -> ok;
		_ -> notify(S1, worker, W)
	end,
	{noreply, S1};

handle_info({'EXIT', Pid, Reason}, S) ->
	log:log("dpool: worker ~p has exited with reason ~p -> restarting~n", [Pid, Reason]),
	{_, NS} = restart_worker(Pid, S),
	{noreply, NS};


handle_info(Req, S) ->
	log:log("dpool: unexpected info: ~p~n", [Req]),
	{noreply, S}.


terminate(Reason, _S) ->
	log:log("dpool: terminating for reason ~p~n", [Reason]).

code_change(_OldVsn, S, _Extra) -> {ok, S}.


% interface
start_link() ->
	gen_server:start_link(?MODULE, [], []).

