[Wiki](../index.md) › [Compiler and build](index.md)

# A new owner takes a move or a written clone, never a hidden copy

Verified: 2026-11-24, from a repro on main where `Box(self.rows[0])` and `Box(xs)` deep-copied; Chinmay asked for the hidden copy to go.

Rule: a constructor argument, a `move` parameter's argument, and a list or map literal element that is a field, element or borrowed parameter of a type that owns memory is a checker error (`own/moves.c`, `check_handed_on` and `check_place_handed_on`): write `.clone()`, or use the field at the last use of its record. Lowering used to copy silently in `take_ownership` (`fn_implicit_clone`); the checker now stops the program before that.

Decision (Chinmay, 2026-11-24, "they should move"): `ok(x)`, `some(x)`, `error(x)` and a returned, bound or stored `x or default` move their argument like any constructor, so a borrowed one needs `.clone()` or a `move` parameter. This replaces the 2026-11-05 boundary-copy ruling for these.

Refinement (same day): `x or default` read in place (a receiver, an operand, a borrowed argument) copies nothing and needs no `.clone()`. Lowering (`lower_or_view`) answers a view of `x`'s payload or of the default; the default is moved into a holder optional the enclosing scope owns, empty on the present path. Only a handed-on result is checked (`check_or_left` in `own/moves.c`). Resources keep the old path. This exposed a bug in `opt_range_len.c`: a join with a source it knew nothing about took the origin of its other sources, so `list.len` folded to a wrong constant; such a join is now mixed.

Left out on purpose, so a later change does not widen it by accident:
- Function values, interfaces and opaque native handles: no `.clone()` exists to write, and wrapping an interface with a clone fails in lowering.
- Generic bodies: checked once with the type still a variable, and an instance only reports resources.

Cause found on the way: `ms_own_call_borrows` ignored a declared `move` result on an `extern fn`, so the result of `msstd_net_connection_share(...)` counted as a view of its argument. It now reads the declaration.

Copy sites are found with `MS_COPY_PROBE=1` (read in `lower_init`) and `make copy-check`; the plan for returns is `design/proposals/borrow-results-in-c.md`.

Update (2026-11-26, #7178): `make copy-check` used to select no test (`--match "no test is selected"`), so test bodies were never lowered and it reported 1 site; it now runs each fixture's tests and counted 219 copies in 83 programs (181 in 76 after the `?` work below). Each probe line ends with the compiler site (`file:line` of the `fn_implicit_clone` call), so group a sweep by that column to see the classes: `take_ownership` (the final clone), bound natives (`lower_funcval.c`), entry places (`lower_close.c`), boxed Optional views (`lower_list.c`), `or`, closures.

`?` on the borrowing variant of a call's result (`&T!`, `&T?!`) takes the error out of the variant when the callee built it (case 1), so it copies nothing; an error an argument holds (case 2) is copied by the relay (`fn_relay_clone`, not a hidden copy: `?` has no place for `.clone()`, and the checker already requires `f(..).clone()?` when the operand borrows a place someone else owns, `own/relays.c`). `error(cause)` of a borrowed `cause` in a `&T!` function answers a borrow (case 2), not a copy. `(f()?) or d` read by an owner moves the payload out of the Result.

Update (2026-11-26, #7178 part 6): a field or `var` lend of an element or entry (`guard.items[0].body.append_bytes(x)`, `m[k]` passed as a `var` argument) takes the element out of its cell with a hole (`fn_take_place`, `fn_field_hole`: the zero of every type drops as nothing) and `fn_put_place` refills it; it never copies the element. `field_path` accepts an element root for this. A map held by a name is lent in place whether or not the receiver is `var` (`fn_place_address` accepts `lists_in_place`), like a list element, because the checker already requires `var` at the call site.

Update (2026-11-26, #7178 part 7, the flip): `implicit_clone_is_error` is `true` in `lower_scope.c`, so a hidden copy is a compile error ("this value would be copied implicitly") and `copy-check` sweeps 1879 programs at 0 copies. What got it there:
- A boxed Optional (`&T?` of a recursive `T`) views a list element's own cell with `MOP_OptViewAt`; its block layout equals the payload's standalone layout.
- `var x = xs.slice(..)?` / `.get_or(..)` of a view needs `.clone()` (`declared_view_call`, `declares_view` in `own/borrows.c`).
- A native that views its first argument (`@borrows`, a result of the argument's type: `trim`, `view`) is a borrow result in MIR (`MirExtern.views`, `result_is_borrow`), so a `&String` function returns `text.trim()` with no copy. Lists of views (`split`, `lines`) stay owned lists. The optimizer's `string_view_value` fast path answers a borrow (`ret_borrowed`, `vf_piece` loads instead of takes), and the hand-built `split_at`/`split_first` externs keep the owned view their loops expect.
- `Map[K, V?].get_or` is a view: an Optional value is stored as it is and `V??` is `V?`, so the entry is the answer (`fn_map_entry_view`), and `x or d` with a nullable result and a name default picks one of two views (`lower_or_nullable_view`).
- A bound method value (`" a ".trim`) is a function value that answers an owned result, so its thunk copies a view with `fn_relay_clone`, like `?` does.
- `xs.slice(a, b).get_or([])` moves its receiver into `get_or`: write `xs.slice(a, b).clone().get_or([])` (the stdlib already does).
