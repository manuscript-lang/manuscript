import {new_lock, Lock} from "@std/lock.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal from "@std/test.ms"
import {milliseconds, sleep} from "@std/time.ms"

fn write_slowly(box: Lock[List[Int]]) Int:
    var held = box.lock()
    held.value.append(1)
    sleep(milliseconds(20))
    held.value.append(2)
    return 0

fn read(box: Lock[List[Int]]) Int:
    return box.get().length()

test "a read while a writer holds the lock waits for the value back":
    let box = new_lock(List[Int]())
    var group = TaskGroup[Int]()
    let writer = box
    let reader = box
    group.spawn(fn ch: write_slowly(writer))
    group.spawn(fn ch: read(reader))

    let results = try group.results()
    group.close()
    try expect_equal(results[1], 2)
