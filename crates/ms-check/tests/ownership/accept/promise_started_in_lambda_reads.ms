import promise from "@std/concurrency/promise.ms"

fn run() Int:
    xs := [1, 2]
    ps := [1, 2].map(fn i:
        mine := xs.clone()
        return promise[Int](fn: ok(mine.length() + i))
    )
    return ps.length() + xs.length()
