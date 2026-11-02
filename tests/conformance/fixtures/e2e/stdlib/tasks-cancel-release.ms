# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"

# A cancelled task leaves its frames by a jump, so the runtime must drop what they own.
# `make leak-check` runs this program against a counting runtime: any live block at exit fails.

fn hold_and_sleep() Int:
    var big = List[Int](reserve: 100000)
    for i in 0..100000:
        big.append(i)
    sleep(nanoseconds(10000000000))
    return big.length()

fn hold_in_callee() Int:
    var words = List[String]()
    for i in 0..1000:
        words.append("word number {i}")

    let total = hold_and_sleep()
    return total + words.length()

fn group_timeout() Unit:
    let group = TaskGroup[Int](timeout: nanoseconds(1000000))
    group.spawn(fn ch: hold_in_callee())

    let _ = group.wait()

fn task_timeout() Unit:
    let group = TaskGroup[Int]()
    let held = group.spawn(fn ch: hold_in_callee(), timeout: nanoseconds(1000000))
    let _ = held.result()

fn leave_group() Unit:
    let group = TaskGroup[Int]()
    group.spawn(fn ch: hold_in_callee())
    sleep(nanoseconds(1000000))

export fn main() Int:
    for round in 0..5:
        group_timeout()
        task_timeout()
        leave_group()

    stdout().write("cancelled tasks released their values\n").get()
    return 0
