-module(basins).
-export([start/1, start/2, attach/1, attach/2]).


start(Max) -> start(Max, basins).

start(Max, Name) ->
	{ok, Pool} = dpool:start_link(),
	true = register(Name, Pool),
	ok = gen_server:call(Pool, subscribe),
	log:log("spawned pool ~p at node ~p, registered as ~p~n", [Pool, node(), Name]),
	wait(Pool, Max).


prime_test(Pid, N) ->
	fun() ->
		case os:getenv("DEBUG") of
			false -> ok;
			_ -> timer:sleep(1000)
		end,
		Pid ! {prime, N, prime_test:is_prime(N)}
	end.


last_state(Last) ->
	receive {dpool, C, L} -> last_state({C, L})
	after 0 -> Last
	end.


wait(Pool, Max) -> wait(Pool, Max, 0).

wait(Pool, 1, 0) ->
	io:format("all done~n"),
	exit(Pool, shutdown);

wait(Pool, N, Wip) ->
	io:format("~p (~p+~p) numbers to test~n", [N+Wip, Wip, N]),
	receive
		{dpool, Capacity, Load} ->
			{NewCapacity, NewLoad} = last_state({Capacity, Load}),
			if N =< 1 ->
				log:log("waiting for ~p workers to finish~n", [Wip]),
				wait(Pool, N, Wip);
			true ->
				case NewLoad >= NewCapacity of
				true ->
					log:log("dpool is overloaded (~p/~p) -> waiting~n", [NewLoad, NewCapacity]),
					wait(Pool, N, Wip);
				false ->
					log:log("dpool load is ~p/~p -> running new worker (~p)~n", [NewLoad, NewCapacity, N]),
					gen_server:call(Pool, {start, prime_test(self(), N)}),
					wait(Pool, N-1, Wip+1)
				end
			end;
		{prime, P, true} ->
			log:log("~p is prime~n", [P]),
			wait(Pool, N, Wip-1);
		{prime, P, false} ->
			log:log("~p is not prime~n", [P]),
			wait(Pool, N, Wip-1);
		Unexpected ->
			log:log("unexpected msg: ~p~n", [Unexpected]),
			wait(Pool, N, Wip)
	end.


attach(Master) -> attach(basins, Master).

attach(Name, Master) ->
	case net_kernel:connect(Master) of
		true -> ok;
		false -> error({cannot_connect, Master})
	end,
	case gen_server:call({Name, Master}, {attach, node()}) of
		ok -> ok;
		Reply -> error({cannot_attach, Reply})
	end,
	monitor_node(Master, true),
	monitor(process, {Name, Master}),
	receive
		{nodedown, Master} ->
			log:log("master node ~p down~n", [Master]);
		{'DOWN', Ref, process, {Name, Master}, Reason} ->
			log:log("master process ~p has exited for reason ~p~n", [Ref, Reason]);
		Unexpected ->
			log:log("unexpected: ~p~n", [Unexpected])
	end.

