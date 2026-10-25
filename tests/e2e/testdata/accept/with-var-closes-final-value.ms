from "@std/core.ms" import Closeable
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal
from "@std/time.ms" import duration, sleep

type Counter:
    value: Int
    log: Shared[List[Int]]

impl Closeable for Counter:
    var def close() -> Unit:
        with var seen = lock(self.log):
            seen.value.append(self.value)

def count_then_wait(log: Shared[List[Int]]) -> Int:
    with var counter = Counter(value: 0, log: log):
        counter.value = 7
        sleep(duration(5000000000))

    return 0

test "a with var block closes the value it ended with":
    let log: Shared[List[Int]] = share([])
    with var counter = Counter(value: 0, log: log):
        counter.value = 5
    log.get().clone() | try expect_equal([5])

test "a cancelled with var block closes the value it had reached":
    let log: Shared[List[Int]] = share([])
    let mine = log

    with let group = TaskGroup[Int](timeout: some(duration(20000000))):
        group.spawn(lambda ch: count_then_wait(mine))
        group.wait()

    log.get().clone() | try expect_equal([7])
