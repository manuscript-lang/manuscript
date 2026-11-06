// Stack growth cost: a loop that crosses the first slot boundary on every call, the same loop
// without a crossing, both on the main task, then a 900k-frame recursion. See README.md.
import owned_promise from "@std/concurrency/promise.ms"
import monotonic_time from "@std/os/system.ms"
import read_file from "@std/os/fs.ms"

fn depth(n: Int) Int:
    if n == 0:
        return 0

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
    let p = owned_promise[Int, Int](n, fn a: ok(loop_depth(a, rounds)))
    return p.wait().get()

export fn main() Int:
    // Crossing cost: the same loop just below and just above the first slot's boundary.
    let rounds = 20000
    let t0 = monotonic_time()
    let below = in_task(3000, rounds)
    let t1 = monotonic_time()
    let above = in_task(3400, rounds)
    let t2 = monotonic_time()
    let main_below = loop_depth(3000, rounds)
    let t3 = monotonic_time()
    let main_above = loop_depth(3400, rounds)
    let t4 = monotonic_time()
    print("task 3000 frames x {rounds}: {(t1 - t0) / 1000000} ms ({below})")
    print("task 3400 frames x {rounds}: {(t2 - t1) / 1000000} ms ({above})")
    print("main 3000 frames x {rounds}: {(t3 - t2) / 1000000} ms ({main_below})")
    print("main 3400 frames x {rounds}: {(t4 - t3) / 1000000} ms ({main_above})")

    // Deep recursion: 900k frames in a task and on the main task.
    let t5 = monotonic_time()
    let deep = in_task(900000, 1)
    let t6 = monotonic_time()
    let main_deep = depth(900000)
    let t7 = monotonic_time()
    print(
        "task 900k frames: {(t6 - t5) / 1000000} ms ({deep}); main: {(t7 - t6) / 1000000} ms ({main_deep})"
    )
    status("after")
    return 0
