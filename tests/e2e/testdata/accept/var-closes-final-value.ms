import Closeable from "@std/core.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal from "@std/test.ms"
import {nanoseconds, sleep} from "@std/time.ms"

type Counter:
    value: Int
    log: Lock[List[Int]]

impl Closeable for Counter:
    var fn close() Unit:
        var seen = self.log.lock()
        seen.value.append(self.value)

fn count_then_wait(log: Lock[List[Int]]) Int:
    var counter = Counter(value: 0, log: log)
    counter.value = 7
    sleep(nanoseconds(5000000000))
    counter.close()
    return 0

test "a var binding closes the value it ended with":
    let log: Lock[List[Int]] = new_lock([])
    var counter = Counter(value: 0, log: log)
    counter.value = 5
    counter.close()
    log.get().clone() | try expect_equal([5])

test "a cancelled var binding closes the value it had reached":
    let log: Lock[List[Int]] = new_lock([])
    let mine = log
    var group = TaskGroup[Int](timeout: some(nanoseconds(20000000)))
    group.spawn(fn ch: count_then_wait(mine))

    let _ignored = group.wait()
    group.close()
    log.get().clone() | try expect_equal([7])
