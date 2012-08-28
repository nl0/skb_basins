-module(basins).
-export([start/1, start/2, attach/1, attach/2]).


start(Max) -> start(Max, basins).

start(Max, Name) ->
	{ok, Pool} = dpool:start_link(),
	true = register(Name, Pool),
	ok = gen_server:call(Pool, subscribe),
	log:log("spawned pool ~p at node ~p, registered as ~p~n", [Pool, node(), Name]),
	{ok, FileName} = application:get_env(skb_basins, file),
	{ok, File} = file:open(FileName, [write]),
	PrimeHandler = fun(P, IsLast) ->
		Fmt = case IsLast of
			last -> "~p~n";
			not_last -> "~p, "
		end,
		io:fwrite(File, Fmt, [P])
	end,
	wait(Pool, PrimeHandler, Max),
	file:close(File).


prime_test(Pid, N) ->
	fun() ->
		case application:get_env(skb_basins, debug) of
			{ok, false} -> ok;
			{ok, true} -> timer:sleep(1000)
		end,
		Pid ! {prime, N, prime:is_prime(N)}
	end.


last_state(Last) ->
	receive {dpool_state, L, C, Q} -> last_state({L, C, Q})
	after 0 -> Last
	end.


wait(Pool, PrimeHandler, Max) -> wait(Pool, PrimeHandler, Max, 0).

wait(Pool, PrimeHandler, 2, 0) ->
	PrimeHandler(2, last),
	io:format("all done~n"),
	exit(Pool, shutdown);

wait(Pool, PrimeHandler, N, Wip) ->
	io:format("~p (~p+~p) numbers to test~n", [N+Wip-2, Wip, N-2]),
	receive
		{dpool_state, L, C, Q} ->
			{LastL, LastC, LastQ} = last_state({L, C, Q}),
			if N =< 2 ->
				log:log("waiting for ~p workers to finish~n", [Wip]),
				wait(Pool, PrimeHandler, N, Wip);
			true ->
				case LastL >= LastC of
				true ->
					log:log("dpool is overloaded: ~p/~p (~p) -> waiting~n", [LastL, LastC, LastQ]),
					wait(Pool, PrimeHandler, N, Wip);
				false ->
					log:log("dpool load is ~p/~p (~p) -> running new worker (~p)~n", [LastL, LastC, LastQ, N]),
					gen_server:call(Pool, {start, prime_test(self(), N)}),
					wait(Pool, PrimeHandler, N-1, Wip+1)
				end
			end;
		{dpool_worker, _} -> wait(Pool, PrimeHandler, N, Wip);
		{prime, P, true} ->
			log:log("~p is prime~n", [P]),
			PrimeHandler(P, not_last),
			wait(Pool, PrimeHandler, N, Wip-1);
		{prime, P, false} ->
			log:log("~p is not prime~n", [P]),
			wait(Pool, PrimeHandler, N, Wip-1);
		Unexpected ->
			log:log("unexpected msg: ~p~n", [Unexpected]),
			wait(Pool, PrimeHandler, N, Wip)
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
			log:log("master node ~p down~n", [Master]),
			monitor_node(Master, false);
		{'DOWN', Ref, process, {Name, Master}, Reason} ->
			log:log("master process ~p has exited for reason ~p~n", [Ref, Reason]);
		Unexpected ->
			log:log("unexpected: ~p~n", [Unexpected])
	end.

