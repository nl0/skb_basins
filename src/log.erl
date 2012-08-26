-module(log).
-export([log/1, log/2]).


log(S) -> do_log([S]).

log(Format, Terms) -> do_log([Format, Terms]).

do_log(A) ->
	case os:getenv("DEBUG") of
		false -> ok;
		_ -> apply(io, format, A)
	end.

