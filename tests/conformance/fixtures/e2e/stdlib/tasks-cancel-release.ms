# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/time.ms" import nanoseconds, sleep

# A cancelled task leaves its frames by a jump, so the runtime must drop what they own.
# `make leak-check` runs this program against a counting runtime: any live block at exit fails.

def hold_and_sleep() -> Int:
    var big = List[Int](reserve: 100000)
    for i in 0..100000:
        big.append(i)
    sleep(nanoseconds(10000000000))
    return big.length()

def hold_in_callee() -> Int:
    var words = List[String]()
    for i in 0..1000:
        words.append(f"word number {i}")

    let total = hold_and_sleep()
    return total + words.length()

def group_timeout() -> Unit:
    let group = TaskGroup[Int](timeout: some(nanoseconds(1000000)))
    group.spawn(lambda ch: hold_in_callee())

    let _ = group.wait()

def task_timeout() -> Unit:
    let group = TaskGroup[Int]()
    let held = group.spawn(
        lambda ch: hold_in_callee(), timeout: some(nanoseconds(1000000))
    )
    let _ = held.result()

def leave_group() -> Unit:
    let group = TaskGroup[Int]()
    group.spawn(lambda ch: hold_in_callee())
    sleep(nanoseconds(1000000))

export def main() -> Int:
    for round in 0..5:
        group_timeout()
        task_timeout()
        leave_group()

    stdout().write("cancelled tasks released their values\n").get()
    return 0
