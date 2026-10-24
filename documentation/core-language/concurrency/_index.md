+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

Run several pieces of work at once with a `TaskGroup`, or spread CPU-bound work over cores with a `WorkerGroup`. Tasks are cooperative and run on one thread, so there is no `async` or `await`: any function can wait, and callers do not change.

1. [Task groups](task-groups.md)
2. [Worker threads](workers.md)
3. [Process groups](process-groups.md): the same shape, in child processes.

Tasks share one thread; workers run on threads of their own and share nothing. Both talk to their starter over a two-way `Channel`. See `proposals/taskgroup.md`, `proposals/channels.md` and `proposals/worker-threads.md`.
