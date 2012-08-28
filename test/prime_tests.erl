-module(prime_tests).
-include_lib("eunit/include/eunit.hrl").


is_prime_test() ->
	?assert(prime:is_prime(1)),
	?assert(prime:is_prime(2)),
	?assert(prime:is_prime(3)),
	?assertNot(prime:is_prime(4)).

