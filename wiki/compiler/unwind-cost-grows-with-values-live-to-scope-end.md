[Wiki](../index.md) › [Compiler and build](index.md)

# Unwind cost grows with the values live to scope end

Verified (2026-11-14, Debug build, x86-64): in a program that starts tasks, the unwind pass registers a cleanup for every owned value live at each place that can fault or park, and again in each fault block. A Debug build keeps owned values live to scope end, so a function of n statements that each make a list needs code and frame growing with n squared. 100 such statements compiled to 3 MB of code and a 983 KB frame, against 11 KB without a promise in the program; a task stack slot is 512 KiB, so `ms test` (each file runs in a promise) died with "stack overflow" while `ms run`, whose main task has a 256 MiB region, ran the same function.

Task programs therefore drop at the last use in any function over `TASK_LONG_FUNCTION_INSTS` (300) instructions, as other programs do above 4000. The frame is then linear: about 330 bytes per four-line statement, so roughly 1,500 such statements still approach the slot. A function with a frame near 512 KiB overflows because only cyclic functions check the stack; growing a segment cannot help, since a segment is one slot.

Apply when: changing the unwind pass, `lastuse`, or the long-function threshold. Verify: fixture `task-long-function` (fails with exit 67 before).
