import Closeable from "@std/core.ms"
import {Shared, share} from "@std/shared.ms"
import lock from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal from "@std/test.ms"
import {nanoseconds, sleep} from "@std/time.ms"

type Counter:
    value: Int
    log: Shared[List[Int]]

impl Closeable for Counter:
    var fn close() Unit:
        with var seen = lock(self.log):
            seen.value.append(self.value)

fn count_then_wait(log: Shared[List[Int]]) Int:
    with var counter = Counter(value: 0, log: log):
        counter.value = 7
        sleep(nanoseconds(5000000000))

    return 0

test "a with var block closes the value it ended with":
    let log: Shared[List[Int]] = share([])
    with var counter = Counter(value: 0, log: log):
        counter.value = 5
    log.get().clone() | try expect_equal([5])

test "a cancelled with var block closes the value it had reached":
    let log: Shared[List[Int]] = share([])
    let mine = log

    with let group = TaskGroup[Int](timeout: some(nanoseconds(20000000))):
        group.spawn(fn ch: count_then_wait(mine))

        let _ignored = group.wait()

    log.get().clone() | try expect_equal([7])
