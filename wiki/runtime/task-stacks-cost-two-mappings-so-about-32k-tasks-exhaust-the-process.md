[Wiki](../index.md) › [Runtime](index.md)

# Task stacks cost two mappings, so about 32k tasks exhaust the process

Verified: each task stack is a 256 MiB slot with an `mprotect` guard, which splits the mapping (2 VMAs per task; `vm.max_map_count` is 65530 by default). Past ~32k live tasks the guard `mprotect` fails with ENOMEM, and pool threads cannot start either. Before the fix a failed guard was ignored and a pool job with no thread waited forever (`read_file` x 40,000 hung); now `create` returns null ("cannot allocate a task stack: too many tasks at once") and `pool::submit` runs an orphaned job inline. Task-backed I/O promises (`owned_promise`) count against this limit; native and pool promises do not (#2440).

Apply when: changing stack allocation, the blocking pool, or adding another per-operation task.
Evidence: `crates/ms-rt/src/task.rs` `stack::create`, `crates/ms-rt/src/glue/pool.rs` `submit`, issue #2483.
Verify: 40,000 concurrent `read_file` promises fault with the message in about a second instead of hanging.
