# The callee owns what it is handed, and the ownership verifier runs in every build

- The verifier runs after elaboration in every build (debug and release share the optimize pipeline). A fixture that "builds" without it proves nothing; sweeps must use the current binary and a baseline built from current main.
- A call that takes a value moves it: the caller steps aside (`scope.disown`), the callee releases it. Lent `var` arguments (`VarSlot`) and writebacks end at the call or at cancel; default-argument code lowers in the caller's environment (`LowerOuterEnv`).
- An owned variable read inside a closing scope is pinned (`pin_outer_vars`) and unpinned with `scope.unpin` on paths that leave the scope.
- A member read that is the place of a native call (`fn->placing_member`) is not a move. A call whose result borrows from a value built in the call (`built_source`) is not returned borrowed.
- Function-value adapter wrappers own what the outer type gives them: a resource closes through a closing slot after the call, any other owner is dropped.
- A call typed `Never` ends the block; arguments and conditions built over it get an `undef` of the parameter type, and a lambda whose end is unreachable ends in `unreachable`.
- The whole-program slot analysis and vtable seeding in `mir_unwind*.c` are not dead under callee-owns: removing them needs explicit slot-parameter modes in the callee signature.
