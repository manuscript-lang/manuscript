import Closeable from "@std/core.ms"
import Shared, share, lock from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

type Counter:
    value: Int
    log: Shared[List[Int]]

impl Closeable for Counter:
    var fn close() Unit!:
        var seen = lock(self.log)
        seen.value.append(self.value)
        return ok(unit)

fn count_then_wait(log: Shared[List[Int]]) Int:
    var counter = Counter(value: 0, log: log)
    counter.value = 7
    sleep(nanoseconds(5000000000))
    counter.close().get(none)
    return 0

test "a var binding closes the value it ended with":
    let log: Shared[List[Int]] = share([])
    var counter = Counter(value: 0, log: log)
    counter.value = 5
    try counter.close()
    log.get().clone() | try expect_equal([5])

test "a cancelled var binding closes the value it had reached":
    let log: Shared[List[Int]] = share([])
    let mine = log
    var group = TaskGroup[Int](timeout: nanoseconds(20000000))
    group.spawn(fn ch: count_then_wait(mine))

    let _ignored = group.wait()
    try group.close()
    log.get().clone() | try expect_equal([7])
