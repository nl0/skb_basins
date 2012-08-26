-module(dpool).
-behaviour(gen_server).
-record(state, {slaves=[], subscribers=[], workers=[]}).
-record(slave, {node, capacity=2, load=0}).
-record(worker, {node, f, pid}).
-export([
	init/1,
	handle_call/3, handle_cast/2, handle_info/2,
	terminate/2, code_change/3,
	start_link/0
]).


%TODO: use some kind of queue to limit load

% core functionality
calc_capacity(Node) -> rpc:call(Node, erlang, system_info, [schedulers])+1.


get_capacity(#state{slaves=Slaves}) ->
	lists:sum([Slave#slave.capacity || Slave <- Slaves]).

get_load(#state{slaves=Slaves}) ->
	lists:sum([Slave#slave.load || Slave <- Slaves]).


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


notify(S = #state{subscribers=Subs}) ->
	log:log("dpool: load: ~p/~p~n", [get_load(S), get_capacity(S)]),
	[Sub ! {dpool, get_capacity(S), get_load(S)} || Sub <- Subs],
	ok.


get_nodes_capacity(#state{slaves=Slaves}) ->
	lists:keysort(2, lists:map(fun(Slave) ->
		{Slave#slave.node, Slave#slave.capacity-Slave#slave.load}
	end, Slaves)).

choose_node(S) ->
	case get_nodes_capacity(S) of
		[] -> error(no_workers);
		Nodes -> element(1, hd(Nodes))
	end.


start_worker(F, S) -> start_worker(choose_node(S), F, S).

start_worker(Node, F, S = #state{slaves=Slaves}) ->
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

restart_worker(Pid, S) -> restart_worker(Pid, choose_node(S), S).

restart_worker(Pid, Node, S) ->
	case remove_worker(Pid, S) of
		A = {not_running, _} -> A;
		{Worker, NS} -> start_worker(Node, Worker#worker.f, NS)
	end.


% callbacks
init(_Args) ->
	process_flag(trap_exit, true),
	{ok, #state{}}.


handle_call(capacity, _From, S) -> {reply, get_capacity(S), S};

handle_call(load, _From, S) -> {reply, get_load(S), S};


handle_call({attach, Node}, From, S) ->
	handle_call({attach, Node, calc_capacity(Node)}, From, S);

handle_call({attach, Node, Capacity}, _From, S) ->
	{Reply, NS} = attach(Node, Capacity, S),
	notify(NS),
	{reply, Reply, NS};


handle_call({detach, Node}, _From, S) ->
	{Reply, NS} = detach(Node, S),
	notify(NS),
	{reply, Reply, NS};


handle_call(subscribe, {Pid, _Ref}, S) ->
	%TODO: DRY f(label, tuple) -> {label, tuple...}
	{Reply, NS} = subscribe(Pid, S),
	{reply, Reply, NS};

handle_call(unsubscribe, {Pid, _Ref}, S) ->
	{Reply, NS} = unsubscribe(Pid, S),
	{reply, Reply, NS};


handle_call({start, F}, _From, S) ->
	log:log("dpool: starting worker ~p~n", [F]),
	{Worker, NS} = start_worker(F, S),
	notify(NS),
	{reply, Worker, NS}.

handle_cast(Req, S) ->
	log:log("dpool: unexpected cast: ~p~n", [Req]),
	{noreply, S}.


handle_info({nodedown, Node}, S) ->
	log:log("dpool: node ~p down~n", [Node]),
	{_, NS} = detach(Node, S),
	notify(NS),
	{noreply, NS};


handle_info({'EXIT', Pid, normal}, S) ->
	log:log("dpool: worker ~p has exited normally~n", [Pid]),
	{_, NS} = remove_worker(Pid, S),
	notify(NS),
	{noreply, NS};

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

