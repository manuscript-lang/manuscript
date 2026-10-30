import stdout from "@std/io.ms"
import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal from "@std/test.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn hold(box: Lock[List[Int]]) Int:
    var guard = box.lock()
    guard.value.append(2)
    sleep(nanoseconds(5000000000))
    guard.close()
    return 0

fn add_slowly(box: Lock[List[Int]]) Int:
    var guard = box.lock()
    guard.value.append(1)
    sleep(nanoseconds(2000000))
    guard.value.append(2)
    guard.close()
    return 0

fn add(box: Lock[List[Int]], value: Int) Int:
    var guard = box.lock()
    guard.value.append(value)
    guard.close()
    return value

test "a task cancelled while holding the lock puts the payload back":
    let box: Lock[List[Int]] = new_lock([1])
    let mine = box
    var group = TaskGroup[Int](timeout: some(nanoseconds(20000000)))
    group.spawn(fn ch: hold(mine))

    let _ignored = group.wait()
    group.close()
    box.get().clone() | try expect_equal([1, 2])

    var guard = box.lock()
    guard.value.append(3)
    guard.close()
    box.get().clone() | try expect_equal([1, 2, 3])

test "a second lock waits for the first guard":
    let box: Lock[List[Int]] = new_lock([])
    let first = box
    let second = box
    var group = TaskGroup[Int]()
    let a = group.spawn(fn ch: add_slowly(first))
    let b = group.spawn(fn ch: add(second, 3))
    let _first_done = try a.result()
    let _second_done = try b.result()
    group.close()
    box.get().clone() | try expect_equal([1, 2, 3])
