# A returned or stored closure may not capture a borrowed parameter

The lowering copied (`fn_implicit_clone`) a borrowed parameter into an escaping closure, a hidden copy. `check_lambda` (`own/moves.c`) now rejects it: take the parameter with `move`, or capture a `.clone()`. A function value is exempt: it is shared. A local closure that does not escape still borrows. Std sites that did this (`Listener.accept`, `connect`, `access_log`, `Gen.zip`, `constant`, `element_of`, `one_of`) clone before the closure, as `connect` already did for its address.
