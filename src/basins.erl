-module(basins).
-export([solve/1]).


solve(Max) ->
	{ok, Srv} = prime_server:start_link([self(), Max, failing]),
	io:format("spawned srv ~p~n", [Srv]),
	wait(Srv).


wait(Srv) ->
	receive
		{prime, N} ->
			io:format("~p is prime~n", [N]),
			wait(Srv);
		{state, N, NWorkers} ->
			io:format("~p workers, ~p left~n", [NWorkers, N]),
			wait(Srv);
		done ->
			io:format("done!~n"),
			ok;
		{unexpected, Msg} ->
			io:format("unexpected msg: ~p~n", [Msg]),
			wait(Srv)
	end.

