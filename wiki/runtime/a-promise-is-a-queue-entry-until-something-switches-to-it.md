[Wiki](../index.md) › [Runtime](index.md)

# A promise is a queue entry until something must switch to it

Verified (2026-11-23, `proposals/fast-tasks-and-promises.md`, numbers in `bench/perf/async-primitives/README.md`): `promise(fn)` queues at every thread count; a waiter runs its entry on its own stack. With one thread the scheduler starts queued entries as tasks at the creator's next switch away (`start_queued` hook), so a promise nobody waits for still runs. Refusing to queue at one thread made every promise pay a stack and two switches (520 ns against 320 ns).

Wake rule: a start wakes a thread only when no thread is looking for work (`ms_workers_nudge`, the looking count in `isolate.c`). A thread woken for work that its waiter ran first keeps looking with a rest that doubles from 20 us to 200 us and sleeps after 20 empty looks; a thread that takes work stops looking and wakes the next one if more is queued. Waking on every start cost a `write` and an `epoll_pwait` per promise (2,300 ns at four threads against 320 ns). The push and the looker's last check are ordered by sequentially consistent accesses of the queue count and the looking count; do not relax either. Sleeping threads are one bit each in one word (`asleep`), so a start that finds nobody asleep does not visit every slot (that scan was 9% of a fork tree).

A wait parks on the promise row with the task's wait word (`ms_task_park_word`), not a token; tokens remain for `wait_any`, groups and waits another thread ends.

Decision (Chinmay, 2026-11-23): a fault report's `task started by:` names only the program line that started the work, as Go does. A start records 12 return addresses in the row with no allocation; walking and copying up to 64 frames was 30% of a deep fork tree. Fixture: `e2e/stdlib/promise-fault-started-line`.

A descriptor waiter that is not a promise: `ms_sched_fd_notify(kind, id, fd, events)` calls a function registered once per kind; use it where a `new`, `io_on_ready`, `fd_ready`, `drop` promise only watched a descriptor.

Apply when: changing promise start, wait, the unstarted-work queue, worker wakes, or the fault report's start site. Check `bench/perf/async-primitives` at 1 and 4 threads, `promise-tree` and a program where one background promise must get its own thread.
