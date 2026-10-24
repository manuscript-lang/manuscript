+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

Run several pieces of work at once with a `TaskGroup`. Tasks are cooperative and run on one thread, so there is no `async` or `await`: any function can wait, and callers do not change.

1. [Task groups](task-groups.md)
2. [Process groups](process-groups.md): the same shape, in child processes.

Planned: `Channel[T]` for passing values between tasks. See `proposals/taskgroup.md` for the design and status.
