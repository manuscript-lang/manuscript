# A returned or stored closure may not capture a borrowed parameter

The lowering copied (`fn_implicit_clone`) a borrowed parameter into an escaping closure, a hidden copy. `check_lambda` (`own/moves.c`) now rejects it: take the parameter with `move`, or capture a `.clone()`. A function value is exempt: it is shared. A local closure that does not escape still borrows. Std sites that did this (`Listener.accept`, `connect`, `access_log`, `Gen.zip`, `constant`, `element_of`, `one_of`) clone before the closure, as `connect` already did for its address.

Same sweep, other sources of hidden copies and their fixes: a `match call()? { v => .. }` owns its arm bindings; a field moved out of an arm binding at its last use keeps the rest in a variable (`bind_payload` as `x := call()` does); `x := moved_param` is an alias, so hand `moved_param` itself on (`if actual != null { return ok(actual) }`); `a or b` where `b` is a borrowed name copies it, so write `b.clone()`. `make copy-check` is at 0.
