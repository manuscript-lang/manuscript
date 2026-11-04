import expect_equal, expect_fault, expect_true from "@std/test/test.ms"
import owned_promise from "@std/concurrency/promise.ms"

fn depth(n: Int) Int:
    if n == 0:
        return 0

    return depth(n - 1) + 1

fn forever(n: Int) Int:
    return forever(n + 1) + 1

// A task starts on a 512 KiB stack slot and grows by guarded segments when a recursion passes
// it: this chain is about 28 MB of frames in a release build, 80 MB in a debug build.
test "a promise task recurses far past its first stack slot":
    let p = owned_promise[Int, Int](200000, fn n: ok(depth(n)))
    try expect_equal(p.wait().get(0), 200000)

// Each call crosses the boundary of the first slot (about 3,200 release frames) and comes
// back; the task keeps its second segment, so the loop allocates nothing after the first pass.
test "a loop at a segment boundary runs in bounded time":
    let p = owned_promise[Int, Int](0, fn n: ok(loop_at_boundary() + n))
    try expect_equal(p.wait().get(0), 3300 * 20000)

fn loop_at_boundary() Int:
    var total = 0
    for unused in 0..20000:
        total += depth(3300)
    return total

// Growth stops at 256 MiB, the main task's own limit, with the stack overflow report.
test "a runaway recursion in a task still faults":
    let p = owned_promise[Int, Int](0, fn n: ok(forever(n)))
    try expect_true(p.wait().is_error())

// A fault deep in a grown stack is caught by a guard opened on the first segment, and the task
// carries on there.
test "a fault inside a grown segment unwinds to its guard":
    let p = owned_promise[Int, Int](0, fn n: ok(catch_in_task() + n))
    try expect_equal(p.wait().get(0), 10000)

fn catch_in_task() Int:
    let message = expect_fault(fn: faulting_depth(10000))
    if message.is_error():
        return -1

    return depth(10000)

fn faulting_depth(n: Int) Unit:
    if n == 0:
        let empty: List[Int] = []
        print(empty[1])
        return

    faulting_depth(n - 1)
