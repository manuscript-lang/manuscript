# Name lookups in a function are indexed, not scanned

A function with thousands of locals took seconds in the checker: `ms_scope_lookup`, the checker's `body_find_any_local`, the shadowing check and the unused-binding read check each scanned every binding in scope per name read, and the unused check also scanned every assignment span per read. A 32,000-line straight-line function took 3.8 s before the optimizer started (quadratic: 8000 lines 0.3 s, 16000 lines 1.0 s).

`MsBindingList` (scope walk) and `Body.locals` now keep a per-name index (`latest[name]` = position + 1, each entry's `shadowed` = the earlier one of its name). Push, truncate and lookup are O(1); the shadowing check follows the `shadowed` chain. The unused check keeps only each candidate's latest assignment span, since an assignment's value is walked before the next assignment. 32,000 lines: 0.47 s, linear.

- Measured 2026-11-23 with generated functions (`v_i := n * i + t; t = t + v_i % 7`) and callgrind inclusive counts at two sizes: divide the larger by the smaller, and any function above about 2.2 for a doubling is superlinear.
- The MIR optimizer is linear in instructions (2.0 per doubling on a function of 16,000 branches) but has a high constant: each pass allocates and zeroes arrays the size of the function, up to 24 simplify rounds, so wall time grows a little faster than linearly from cache effects (4000 branches 1.06 s, 8000 2.3 s, 16000 5.3 s).
