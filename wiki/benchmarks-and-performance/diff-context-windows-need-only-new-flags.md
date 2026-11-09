# Diff context windows need only new flags

A unified diff marks a window around every changed step. Consecutive windows have nondecreasing starts and ends. Marking each whole window revisits the same flags; full-file context makes dense changes quadratic even when there is no edit-distance table to build.

Walk a window backward from its end and stop on the first flag already set. Earlier windows cover the remainder back to the new window's start. Each flag is then set once, without an extra frontier or auxiliary buffer. Preserve the existing bounds before walking, including context zero and the largest Int.

Check exact hunk output for overlapping, adjacent and separated windows, insertion/deletion-only inputs, and unchanged text. Use [the context benchmark](../../bench/perf/diff-context/README.md) for full-file scaling plus default-context, sparse-change and unchanged controls.
