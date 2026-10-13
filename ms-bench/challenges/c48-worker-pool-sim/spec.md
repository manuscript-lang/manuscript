# Worker pool simulation

Simulate a pool of identical workers executing tasks with a bounded waiting queue, priorities and retries,
and report one result per task in **input order**, then per-worker statistics and a summary.

## Input

Tokens on a line are separated by runs of spaces and tabs; blank lines are ignored. The first non-blank line
is the pool definition, all following non-blank lines are tasks. Input is always well formed.

    pool WORKERS QUEUE RETRIES
    task ID ARRIVAL COST [fails=N] [high]

- `WORKERS` >= 1 is the number of workers, numbered `1..WORKERS`. `QUEUE` >= 0 is the capacity of the
  waiting queue. `RETRIES` >= 0 is how many times a failed task may be retried.
- `ID` is an arbitrary token, unique among tasks. `ARRIVAL` >= 0 is the time the task is submitted and
  `COST` >= 1 is how long each attempt runs. All numbers are decimal integers that fit comfortably in 32 bits.
- The optional tokens `fails=N` (`N` >= 0, default 0) and `high` may appear in either order, each at most once.
  `fails=N` means the first `N` attempts of this task fail (an attempt always runs for the full `COST`
  before failing). `high` marks a high-priority task.

Tasks may be listed in any order; the arrival times are not necessarily sorted.

## Rules

Time is an integer. A worker is either idle or running one attempt of one task, which occupies it from the
start time `S` to the end time `S + COST`. There are two FIFO waiting queues, one for high-priority tasks
and one for normal tasks.

At every time `t` at which something happens (an attempt ends or a task arrives), process in this order:

1. **Completions.** For each worker, in ascending worker number, whose attempt ends at `t`: the worker
   becomes idle. If the attempt succeeded (attempt number `a` is greater than the task's `N` in
   `fails=N`) the task is finished successfully. Otherwise, if `a < RETRIES + 1` the task is appended to
   the tail of the queue matching its priority (this ignores the capacity limit, so the combined queue may
   temporarily exceed `QUEUE`); if `a == RETRIES + 1` the task is finished as failed.
2. **Dispatch.** For each idle worker in ascending worker number, while a task is waiting: take the head of
   the high-priority queue if it is not empty, otherwise the head of the normal queue, and start a new
   attempt on that worker at time `t`.
3. **Arrivals.** Tasks with `ARRIVAL == t` are handled in input order (the order they are listed in the
   file). For each: if some worker is idle, the task starts its first attempt on the lowest-numbered idle
   worker at time `t`; otherwise, if the combined length of both queues is less than `QUEUE`, it is appended
   to the queue matching its priority; otherwise it is rejected at time `t`. A rejected task never runs.

The simulation ends when every worker is idle, nothing is waiting and no task has yet to arrive. A worker's
`busy` time is the total of the `COST` of every attempt it ran (including failed attempts). The
`makespan` is the largest end time of any attempt that ran, or 0 if no attempt ran.

## Output

First one line per task, in input order (not time order):

- finished successfully: `ID ok worker=K start=S end=E attempts=A` (`K`, `S`, `E` describe the final,
  successful attempt; `A` is the number of attempts including it);
- failed: `ID failed attempts=A end=E` (`E` is the end time of the last attempt);
- rejected: `ID rejected at=T`.

Then one line per worker, `worker K busy=B`, for `K = 1..WORKERS`, then one line

    summary ok=C failed=F rejected=R makespan=M

counting tasks by outcome. If there are no tasks, only the worker lines and the summary are printed.

## Example

Input:

    pool 2 1 1
    task a 0 5
    task b 0 3
    task c 1 2
    task d 2 4 high
    task e 2 1 fails=1

Output:

    a ok worker=1 start=0 end=5 attempts=1
    b ok worker=2 start=0 end=3 attempts=1
    c ok worker=2 start=3 end=5 attempts=1
    d rejected at=2
    e rejected at=2
    worker 1 busy=5
    worker 2 busy=5
    summary ok=3 failed=0 rejected=2 makespan=5

Here `c` waits in the queue (capacity 1) from time 1 until worker 2 frees up at time 3, so `d` and `e` find
both workers busy and the queue full.
