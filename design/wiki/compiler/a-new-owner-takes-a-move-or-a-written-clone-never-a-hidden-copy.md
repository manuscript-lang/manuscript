[Wiki](../index.md) › [Compiler and build](index.md)

# A new owner takes a move or a written clone, never a hidden copy

Verified: 2026-11-24, from a repro on main where `Box(self.rows[0])` and `Box(xs)` deep-copied; Chinmay asked for the hidden copy to go.

Rule: a constructor argument, a `move` parameter's argument, and a list or map literal element that is a field, element or borrowed parameter of a type that owns memory is a checker error (`own/moves.c`, `check_handed_on` and `check_place_handed_on`): write `.clone()`, or use the field at the last use of its record. Lowering used to copy silently in `take_ownership` (`fn_implicit_clone`); the checker now stops the program before that.

Decision (Chinmay, 2026-11-24, "they should move"): `ok(x)`, `some(x)`, `error(x)` and `x or default` move their argument like any constructor, so a borrowed one needs `.clone()` or a `move` parameter. This replaces the 2026-11-05 boundary-copy ruling for these four. `x or panic(..)` only reads and is not checked.

Left out on purpose, so a later change does not widen it by accident:
- Function values, interfaces and opaque native handles: no `.clone()` exists to write, and wrapping an interface with a clone fails in lowering.
- Generic bodies: checked once with the type still a variable, and an instance only reports resources.

Cause found on the way: `ms_own_call_borrows` ignored a declared `move` result on an `extern fn`, so the result of `msstd_net_connection_share(...)` counted as a view of its argument. It now reads the declaration.

Still copying (not fixed here): returns of a borrowed value, `get_or` defaults and closure captures. `MS_COPY_PROBE=1` (read in `lower_init`) prints each remaining site and `make copy-check` lists them; it counted 25 in 951 programs on 2026-11-24. The plan for returns is `design/proposals/borrow-results-in-c.md`.
