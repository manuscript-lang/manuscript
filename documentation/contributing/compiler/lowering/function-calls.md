+++
title = "Function lowering"
weight = 93
+++

# Function lowering

Functions, closures, and contract methods lower to Go calls that carry a hidden execution context (cancellation, deadlines, host service accessors). A closure also keeps its captured snapshots in an environment object. Source has one function kind, and every function can wait.

- The context carries the current operation, cancellation signal, deadline, cleanup mode, and host roots. Closure creation does not capture the caller's context; invocation supplies it.
- Each loop back-edge polls the stop signal and unwinds through the iteration's cleanup. Cleanup contexts are shielded, so the poll never fires during cleanup. The Rust backend does not poll on loop back edges; it observes the stop signal in runtime calls and I/O.
