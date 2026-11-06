// Memory and time per parked task: starts N promise tasks that park (mode `sleep`, on a timer;
// `deep`, on a timer after a 256-frame call chain, as a handler parks after real work; or
// `read`, after a file read), then reports the process's resident set and page tables.
// `ms run bench/perf/tasks/main.ms -- 1000000 sleep`. Linux only for the report
// (it reads /proc/self/status); the tasks themselves are portable.
import owned_promise, Promise from "@std/concurrency/promise.ms"
import sleep, seconds from "@std/time.ms"
import read_file from "@std/os/fs.ms"
import arguments from "@std/os/env.ms"
import monotonic_time from "@std/os/system.ms"

fn status(label: String) Unit:
    let text = read_file("/proc/self/status", none).wait().get().decode_utf8().get()
    for line in text.lines():
        if line.contains("VmRSS") or line.contains("VmHWM") or line.contains("VmPTE"):
            print(label + " " + line)

fn park_sleep(a: Int) Int!:
    try sleep(seconds(1000)).wait()
    return ok(a)

fn descend(depth: Int, acc: Int) Int:
    if depth == 0:
        return acc

    let scratch: List[Int] = [acc, depth, acc + depth]
    let below = descend(depth - 1, acc + scratch[1])
    return below + scratch.length()

fn park_deep(a: Int) Int!:
    let sum = descend(256, a)
    try sleep(seconds(1000)).wait()
    return ok(sum)

fn park_read(a: Int) Int!:
    let data = try read_file("/proc/self/stat", none).wait()
    try sleep(seconds(1000)).wait()
    return ok(data.length() + a)

export fn main() Int:
    let args = arguments()
    let n = args[0].parse_int().get()
    let mode = args[1].clone()
    status("before")

    let t0 = monotonic_time()
    var promises: List[Promise[Int]] = []

    for i in 0..n:
        if mode == "sleep":
            promises.append(owned_promise[Int, Int](i, fn a: park_sleep(a)))
        else if mode == "deep":
            promises.append(owned_promise[Int, Int](i, fn a: park_deep(a)))
        else:
            promises.append(owned_promise[Int, Int](i, fn a: park_read(a)))

    let t1 = monotonic_time()

    // Let every task start and park, then let the idle scheduler hibernate them.
    sleep(seconds(3)).wait().get()
    status("parked")
    sleep(seconds(3)).wait().get()
    status("idle")

    let t2 = monotonic_time()
    print("spawn ms " + ((t1 - t0) / 1000000).to_string())
    for p in promises:
        p.cancel()

    let t3 = monotonic_time()
    print("cancel ms " + ((t3 - t2) / 1000000).to_string())
    return 0
