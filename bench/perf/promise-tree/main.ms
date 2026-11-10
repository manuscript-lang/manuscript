import promise, Promise, wait_all from "@std/concurrency/promise.ms"
import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

fn fib(n: Int) Int:
    if n < 2: return n

    return fib(n - 1) + fib(n - 2)

// promise-per-level fib: spawn one half as a promise, compute other inline
fn pfib(n: Int, cutoff: Int) Int!:
    if n < cutoff: return ok(fib(n))

    let m = n - 1
    let p = promise[Int](fn: pfib(m, cutoff))
    let b = try pfib(n - 2, cutoff)
    let a = try p.wait()
    return ok(a + b)

fn work(n: Int) Int!:
    return ok(fib(n))

export fn main() Int:
    let args = arguments()
    let mode = args[0].clone()
    let n = args[1].parse_int().get()
    let k = args[2].parse_int().get()
    let t0 = monotonic()
    var r = 0

    if mode == "fan":
        var ps: List[Promise[Int]] = []
        for i in 0..k:
            ps.append(promise[Int](fn: work(n)))

        let rs = wait_all(ps).get()
        for x in rs:
            r += x
    else if mode == "tree":
        r = pfib(n, k).get()

    print(
        mode + " result " + r.to_string() + " ms " + (
            monotonic().difference(t0).to_nanoseconds()
            / 1000000
        ).to_string()
    )
    return 0
