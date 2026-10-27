from "@std/io.ms" import stdout
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/tasks.ms" import TaskGroup
from "@std/test.ms" import expect_equal
from "@std/time.ms" import nanoseconds, sleep

def hold(box: Shared[List[Int]]) -> Int:
    with var guard = lock(box):
        guard.value.append(2)
        sleep(nanoseconds(5000000000))

    return 0

def add_slowly(box: Shared[List[Int]]) -> Int:
    with var guard = lock(box):
        guard.value.append(1)
        sleep(nanoseconds(2000000))
        guard.value.append(2)

    return 0

def add(box: Shared[List[Int]], value: Int) -> Int:
    with var guard = lock(box):
        guard.value.append(value)
    return value

test "a task cancelled while holding the lock puts the payload back":
    let box: Shared[List[Int]] = share([1])
    let mine = box

    with let group = TaskGroup[Int](timeout: some(nanoseconds(20000000))):
        group.spawn(lambda ch: hold(mine))

        let _ignored = group.wait()

    box.get().clone() | try expect_equal([1, 2])
    with var guard = lock(box):
        guard.value.append(3)
    box.get().clone() | try expect_equal([1, 2, 3])

test "a second lock waits for the first guard":
    let box: Shared[List[Int]] = share([])
    let first = box
    let second = box

    with let group = TaskGroup[Int]():
        let a = group.spawn(lambda ch: add_slowly(first))
        let b = group.spawn(lambda ch: add(second, 3))
        let _first_done = try a.result()
        let _second_done = try b.result()

    box.get().clone() | try expect_equal([1, 2, 3])
