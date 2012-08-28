-module(log).
-export([log/1, log/2]).


log(S) -> do_log([S]).

log(Format, Terms) -> do_log([Format, Terms]).

do_log(A) ->
	case application:get_env(skb_basins, debug) of
		{ok, false} -> ok;
		{ok, true} -> apply(io, format, A)
	end.

