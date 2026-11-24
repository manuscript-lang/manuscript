+++
title = "Background jobs"
weight = 19
+++

# Background jobs

Run work beside the main program: a bounded batch, a queue with a worker, and a timer.

## Process a batch with a concurrency limit

Save as `batch.ms`. `map_concurrent` applies a function to every item with at most `limit` running at once and returns the results in order. The first failure cancels the rest.

<!-- manuscript-example: {"mode":"run","stdout":"[1, 4, 9, 16, 25, 36]\n"} -->
```manuscript
import map_concurrent from "@std/concurrency/resilience.ms"

fn square(n Int) Int:
    return n * n

fn main() Void!:
    squares := map_concurrent([1, 2, 3, 4, 5, 6], 3, square)?
    print(f"{squares}")
```

## Feed a worker through a queue

Save as `worker.ms`. A pipe is the queue: the main program writes jobs, one worker promise reads them, and closing the writer tells the worker no more are coming. The worker returns its result, which `wait` collects.

<!-- manuscript-example: {"mode":"run","stdout":"processed 3 jobs, total 60\n"} -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import ReadStream, pipe from "@std/io/io.ms"

type Summary:
    jobs Int
    total Int

fn work(var jobs ReadStream[Int]) Summary!:
    var summary = Summary(jobs: 0, total: 0)
    for job in jobs:
        summary.jobs += 1
        summary.total += job
    return ok(summary)

fn main() Void!:
    var queue = pipe[Int](capacity: 8)
    var jobs = queue.writer()
    var reader = queue.reader()
    worker := promise(() => work(reader))
    for job in [10, 20, 30]:
        jobs.write(job)?
    jobs.close()?
    done := worker.wait()?
    print(f"processed {done.jobs} jobs, total {done.total}")
```

- The queue holds up to `capacity` jobs; `write` waits when it is full, so a fast producer cannot outrun a slow worker without bound.
- Start several workers with their own readers by giving each producer its own `writer()`; one reader reads one pipe.
- Dropping the `worker` promise before it finishes cancels it, so work never outlives the code that started it.

## Repeat work on an interval

Save as `tick.ms`. A promise can loop and `sleep` between rounds. `sleep` returns a promise, so `.wait()` pauses this task only. Cancelling the promise, by dropping it or when its owner ends, ends a sleep at once, so a long interval never delays shutdown.

<!-- manuscript-example: {"mode":"run","stdout":"tick 1\ntick 2\ntick 3\n"} -->
```manuscript
import promise from "@std/concurrency/promise.ms"
import milliseconds, sleep from "@std/time.ms"

fn ticker(rounds Int) Void!:
    for n in 1..rounds + 1:
        print(f"tick {n}")
        sleep(milliseconds(20)).wait()?
    return ok()

fn main() Void!:
    background := promise(() => ticker(3))
    return background.wait()
```
