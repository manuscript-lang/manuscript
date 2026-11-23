# One huge function must not tier the whole module to -O0

- `size_tier` in `emit_func.c` marks very large functions optnone/optsize. `object.c` ran `llc -O0` for the whole module when any function was optnone, so one big loop-free function (toml `scalar.body`, >8000 lines) gave every function in the module unshared spill slots and overflowed the stack in deep-nesting tests under `ms test`.
- Only the 60000-line tier carries the `"ms-huge"` marker that selects module-wide `llc -O0`. llc -O2 handles a plain optnone function cheaply (measured), so smaller huge functions stay at -O2 for the rest.
- Generated code must not be large straight-line code: `[embed]` now emits data (per-file functions, string literals) instead of a giant function, which also keeps yaml_suite out of the tier.
- Handle slots (`cleanup.push` results) may share a cell only within one block and only when used; cleanups are popped in bulk by discarding an earlier handle, so a pushed slot must stay live until popped. Modeling bulk pops would let `quoted` in yaml fall from 28 KB toward ~3 KB.
