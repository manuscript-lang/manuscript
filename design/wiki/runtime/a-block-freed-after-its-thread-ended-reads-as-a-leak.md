[Wiki](../index.md) › [Runtime](index.md)

# A block freed after its allocating thread ended reads as a leak

Verified (2026-11-24): `cancelled-serve-start-frees-handler` left 64 bytes live in the leak check on Windows and, under load, about 4 runs in 100 on Linux, though no `ms_alloc` block was live at exit. The block is the abandon request a cancelled net wait allocates on its worker thread and the loop thread frees. mimalloc 3 counts a block freed from another thread only when the owner collects its page, and a thread that has ended never does, so the cross-thread free that lands after the worker is joined stays "current".

Fix: a worker runs `ms_quiesce_run()` as it ends (`core/release.h`), and the net loop registers `ms_net_quiesce`, a marker operation that returns once everything queued earlier has run. 0 leaks in 1440 loaded runs after, against about 55 before. Any helper thread that frees what workers allocate needs the same hook; an exit-time `mi_collect` does not help (it changes what `current` means).

Diagnose a "leak" like this first with a probe on `ms_alloc`, `ms_alloc_zeroed`, `ms_realloc` and `ms_free` that lists blocks still live at exit: empty means the counter, not the program, is wrong. Reproduce with 24 parallel copies on 4 cores.
