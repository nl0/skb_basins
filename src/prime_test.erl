-module(prime_test).
-export([
	is_prime/1, failing_is_prime/1,
	start_test_link/2, start_test_link/3,
	start_link/1, start_link/2, init/1
]).
-behaviour(supervisor).



is_prime(N) when N =< 0 -> error;
is_prime(N) when N =< 3 -> true;
is_prime(N) -> is_prime(N, 2, trunc(math:sqrt(N))).

is_prime(_N, R, Sqrt) when R > Sqrt -> true;
is_prime(N, R, _Sqrt) when N rem R == 0 -> false;
is_prime(N, R, Sqrt) -> is_prime(N, R + 1, Sqrt).


failing_is_prime(N) ->
	random:seed(now()),
	case random:uniform(2) of
		1 -> is_prime(N);
		2 -> error(worker_has_failed)
	end.


start_test_link(Pid, PrimeTest, N) ->
	{ok, spawn_link(fun() -> Pid ! {is_prime, N, PrimeTest(N)} end)}.

start_test_link(Pid, N) -> start_test_link(Pid, fun is_prime/1, N).


start_link(Pid) -> supervisor:start_link(?MODULE, [Pid]).
start_link(Pid, PrimeTest) -> supervisor:start_link(?MODULE, [Pid, PrimeTest]).


init(A) ->
	{
		ok,
		{
			{simple_one_for_one, 1000000, 1},
			[{
				?MODULE,
				{?MODULE, start_test_link, A},
				transient,
				infinity,
				worker,
				[?MODULE]
			}]
		}
	}.

