-module(prime_server).
-export([start_link/1]).
-record(state, {pid, n, n_workers=0, max_workers, tester}).


start_link(A) ->
	{ok, spawn_link(fun() -> loop(init(A)) end)}.

init([Pid, Max, failing]) ->
	init([Pid, Max, fun prime_test:failing_is_prime/1]);

init([Pid, Max | A]) ->
	{ok, Tester} = apply(prime_test, start_link, [self() | A]),
	#state{pid=Pid, n=Max, max_workers=4, tester=Tester}.


loop(#state{n=1, n_workers=0, pid=Pid, tester=Tester}) ->
	exit(Tester, shutdown),
	Pid ! done;

loop(S=#state{n=N, n_workers=NWorkers, max_workers=MaxWorkers, tester=Tester}) when NWorkers < MaxWorkers, N > 1 ->
	supervisor:start_child(Tester, [N]),
	loop(S#state{n=N-1, n_workers=NWorkers+1});

loop(S=#state{n=N, n_workers=NWorkers, pid=Pid}) ->
	Pid ! {state, N, NWorkers},
	receive
		{is_prime, N1, IsPrime} ->
			case IsPrime of
				true -> Pid ! {prime, N1};
				false -> noop
			end,
			loop(S#state{n_workers=NWorkers-1});
		Unexpected ->
			Pid ! {unexpected, Unexpected},
			loop(S)
	end.

