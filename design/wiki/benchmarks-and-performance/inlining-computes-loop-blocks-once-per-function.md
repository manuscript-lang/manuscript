[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Inlining computes a function's loop blocks once, not per block

`il_inline_block` reset the loop-membership table for every block, and `il_auto_ok` rebuilt it (a graph over all blocks) whenever a candidate callee had a loop. A function with many calls to looping callees (a `main` calling 2000 functions) rebuilt a whole-function table once per block, and the arena kept every copy: `ms emit --opt` of 2000 small functions peaked at 663 MB and took 2.4 s. Inlining at one site neither creates nor removes a cycle through another existing block, so the table is computed once per function: 219 MB and 1.96 s, identical output.

Lesson: a table indexed by the blocks of a function that is rebuilt per block is quadratic in time and, in an arena, in memory. Check `ms emit --opt` peak memory at 500, 1000 and 2000 functions; it must grow linearly.
