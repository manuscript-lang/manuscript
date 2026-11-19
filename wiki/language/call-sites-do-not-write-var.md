# Call sites do not write `var`

Decision (2026-11-19, Chinmay): a call passes `f(x)` for a parameter declared `var`, as it passes `f(x)` for `move`. The checker takes the mode from the callee's signature (`call_modes`), so the marker added no information. It was the most common first-build failure in agent skill tests (a missing `var` at the call), and agents could not tell it from the real rule, which is the `var` on the parameter and on the argument's own variable.

Kept: exclusive-borrow rules, overlap checks, and the requirement that the argument is a `var` variable or a field of one. A `var` receiver is unchanged (`fn var T.m`).

Transition: the parser still accepts `f(var x)`. The checker ignores it, and lint `MSL136` warns with a fix (`ms lint --fix`); the migration of stdlib, docs and fixtures was done with that fix. Removing the syntax from the parser is the follow-up once no source needs it. Lints that count writes to a name read `ArgSlot.changed` (set from the callee's parameter), not the written marker.
