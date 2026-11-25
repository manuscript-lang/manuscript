# A bound name belongs to the scope outside its statement

A statement whose calls borrow temporary resources lowers in a scope of its own (`lower_scoped`), and the name it binds must outlive it: `bind_scope` names the scope outside. The plain owned binding does this with `scope.disown` and `fn_own(bind_scope - 1)`, the closing binding with `fn_bind_closing_in`. The third path, a name kept in a variable because the `if` after it narrows it (`data := f().wait().to_optional()` then `if data != null`), registered the variable with `fn_scope`, the statement's scope, so the value was released when the statement ended and read afterwards. Release builds miscompiled it silently; checked builds and `ms run` stopped with `used after it was consumed` (found by the agent-bench checker).

Every path that registers the owner of a bound name takes `bind_scope - 1` when `bind_scope` is set (`fn_scope_own_var_in`). Fixture: `narrowed-name-bound-from-temporary-chain`.
