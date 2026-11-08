import promise, wait_all from "@std/concurrency/promise.ms"

fn square(n: Int) Int!:
    return ok(n * n)

export fn main() Int:
    let a = promise(fn: square(3))
    let b = promise(fn: square(4))
    for r in wait_all([a, b]).get(List[Int]()):
        print("{r}")
    return 0
