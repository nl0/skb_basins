-module(basins).
-export([solve/1]).


% TODO: use gen_fsm
solve(Max) ->
	{ok, Tester} = prime_test:start_link(self(), fun prime_test:failing_is_prime/1),
	io:format("spawned tester ~p~n", [Tester]),
	[supervisor:start_child(Tester, [N]) || N <- lists:seq(2, Max)],
	wait(Tester, Max-1).


append_if_true(Cond, List, Item) when Cond -> [Item | List];
append_if_true(Cond, List, _Item) when not Cond -> List.


wait(Tester, Count) -> wait(Tester, Count, []).

wait(_Tester, Count, Results) when Count == 0 -> Results;

wait(Tester, Count, Results) ->
	io:format("waiting for ~p (~p)~n", [Count, Results]),
	receive
		{is_prime, N, IsPrime} ->
			io:format("is_prime, ~p, ~p~n", [N, IsPrime]),
			wait(Tester, Count-1, append_if_true(IsPrime, Results, N));
		Unexpected ->
			io:format("unexpected msg: ~p~n", [Unexpected]),
			wait(Tester, Count, Results)
	end.

