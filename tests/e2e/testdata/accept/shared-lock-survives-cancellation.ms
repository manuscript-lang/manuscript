import stdout from "@std/io/io.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn hold(box: Shared[List[Int]]) Int:
    var guard = lock(box)
    guard.value.append(2)
    sleep(nanoseconds(5000000000))
    guard.close().get(none)
    return 0

fn add_slowly(box: Shared[List[Int]]) Int:
    var guard = lock(box)
    guard.value.append(1)
    sleep(nanoseconds(2000000))
    guard.value.append(2)
    guard.close().get(none)
    return 0

fn add(box: Shared[List[Int]], value: Int) Int:
    var guard = lock(box)
    guard.value.append(value)
    guard.close().get(none)
    return value

test "a task cancelled while holding the lock puts the payload back":
    let box: Shared[List[Int]] = share([1])
    let mine = box
    var group = TaskGroup[Int](timeout: nanoseconds(20000000))
    group.spawn(fn ch: hold(mine))

    let _ignored = group.wait()
    try group.close()
    box.get().clone() | try expect_equal([1, 2])

    var guard = lock(box)
    guard.value.append(3)
    try guard.close()
    box.get().clone() | try expect_equal([1, 2, 3])

test "a second lock waits for the first guard":
    let box: Shared[List[Int]] = share([])
    let first = box
    let second = box
    var group = TaskGroup[Int]()
    let a = group.spawn(fn ch: add_slowly(first))
    let b = group.spawn(fn ch: add(second, 3))
    let _first_done = try a.result()
    let _second_done = try b.result()
    try group.close()
    box.get().clone() | try expect_equal([1, 2, 3])
