# conform: tags=stdlib-shared,stdlib-tasks,tier-io
# conform: phase=run
# conform: timeout=20
from "@std/collections.ms" import range
from "@std/io.ms" import stdout
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import duration, milliseconds, sleep

def holder(box: Shared[Int], nap: Int) -> Int:
    with var g = lock(box):
        sleep(duration(nanoseconds: nap))
    return 0

def waiter(box: Shared[Int]) -> Int:
    with var g = lock(box):
        g.value = g.value + 1
    return 1

export def main() -> Int:
    var served = 0

    for round in range(0, 60):
        let box = share(0)
        let nap = 2000000 + round * 7000

        with let g = TaskGroup[Int]():
            g.spawn(lambda ch: holder(box, nap))
            sleep(duration(nanoseconds: 100000))

            let first = g.spawn(
                lambda ch: waiter(box),
                timeout: some(
                    duration(
                        nanoseconds: nap - 100000 + (
                            round
                            % 7
                        ) * 3000 - 9000
                    )
                )
            )
            let second = g.spawn(lambda ch: waiter(box))
            if second.result().is_ok():
                served += 1

    stdout().write("served " + served.to_string() + "\n")
    return 0
