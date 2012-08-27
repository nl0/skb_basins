-module(prime).
-export([is_prime/1]).


is_prime(N) when N =< 0 -> error;
is_prime(N) when N =< 3 -> true;
is_prime(N) -> is_prime(N, 2, trunc(math:sqrt(N))).

is_prime(_N, R, Sqrt) when R > Sqrt -> true;
is_prime(N, R, _Sqrt) when N rem R == 0 -> false;
is_prime(N, R, Sqrt) -> is_prime(N, R + 1, Sqrt).

