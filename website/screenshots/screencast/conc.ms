import promise, wait_all from "@std/concurrency/promise.ms"

export fn main() Int:
    let a = promise(fn: ok(3 * 3))
    let b = promise(fn: ok(4 * 4))
    print(wait_all([a, b]).get(List[Int]()))
    return 0
