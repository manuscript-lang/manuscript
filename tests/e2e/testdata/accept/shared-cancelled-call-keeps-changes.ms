import Shared from "@std/concurrency/shared.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn append_then_wait(var items: List[Int]) Unit:
    items.append(2)
    sleep(nanoseconds(5000000000))

fn hold(var box: Shared[List[Int]]) Int:
    append_then_wait(var box)
    return 0

fn add_slowly(var items: List[Int]) Unit:
    items.append(1)
    sleep(nanoseconds(2000000))
    items.append(2)

fn add(var box: Shared[List[Int]], value: Int) Int:
    box.append(value)
    return value

fn slowly(var box: Shared[List[Int]]) Int:
    add_slowly(var box)
    return 0

test "a task cancelled inside a call keeps its changes and frees the value":
    var box: Shared[List[Int]] = Shared([1])
    var mine = box
    var group = TaskGroup[Int](timeout: nanoseconds(20000000))
    group.spawn(fn ch: hold(var mine))

    let _ignored = group.wait()
    try group.close()
    box.clone() | try expect_equal([1, 2])
    box.append(3)
    box.clone() | try expect_equal([1, 2, 3])

test "a change from another task waits for the call in progress":
    var box: Shared[List[Int]] = Shared([])
    var first = box
    var second = box
    var group = TaskGroup[Int]()
    let a = group.spawn(fn ch: slowly(var first))
    let b = group.spawn(fn ch: add(var second, 3))
    let _first_done = try a.result()
    let _second_done = try b.result()
    try group.close()
    box.clone() | try expect_equal([1, 2, 3])
