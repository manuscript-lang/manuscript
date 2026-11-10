// Stack growth cost: a loop that crosses the first slot boundary on every call, the same loop
// without a crossing, both on the main task, then a 900k-frame recursion. See README.md.
import owned_task from "@std/concurrency/promise.ms"
import monotonic from "@std/time.ms"
import read_file from "@std/os/fs.ms"

fn depth(n: Int) Int:
    if n == 0: return 0

    return depth(n - 1) + 1

fn loop_depth(n: Int, rounds: Int) Int:
    var total = 0
    for unused in 0..rounds:
        total += depth(n)
    return total

fn status(label: String) Unit:
    let text = read_file("/proc/self/status", none).wait().get().decode_utf8().get()
    for line in text.lines():
        if line.contains("VmRSS") or line.contains("VmPTE"):
            print(label + " " + line)

fn in_task(n: Int, rounds: Int) Int:
    let p = owned_task[Int](fn: ok(loop_depth(n, rounds)))
    return p.wait().get()

fn main() Int:
    // Crossing cost: the same loop just below and just above the first slot's boundary.
    let rounds = 20000
    let t0 = monotonic()
    let below = in_task(3000, rounds)
    let t1 = monotonic()
    let above = in_task(3400, rounds)
    let t2 = monotonic()
    let main_below = loop_depth(3000, rounds)
    let t3 = monotonic()
    let main_above = loop_depth(3400, rounds)
    let t4 = monotonic()
    print(
        "task 3000 frames x {rounds}: {t1.difference(t0).to_nanoseconds() / 1000000} ms ({below})"
    )
    print(
        "task 3400 frames x {rounds}: {t2.difference(t1).to_nanoseconds() / 1000000} ms ({above})"
    )
    print(
        "main 3000 frames x {rounds}: {t3.difference(t2).to_nanoseconds() / 1000000} ms ({main_below})"
    )
    print(
        "main 3400 frames x {rounds}: {t4.difference(t3).to_nanoseconds() / 1000000} ms ({main_above})"
    )

    // Deep recursion: 900k frames in a task and on the main task.
    let t5 = monotonic()
    let deep = in_task(900000, 1)
    let t6 = monotonic()
    let main_deep = depth(900000)
    let t7 = monotonic()
    print(
        "task 900k frames: {t6.difference(t5).to_nanoseconds() / 1000000} ms ({deep}); main: {t7.difference(t6).to_nanoseconds() / 1000000} ms ({main_deep})"
    )
    status("after")
    return 0
