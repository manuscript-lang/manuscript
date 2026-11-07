import Promise, promise from "@std/concurrency/promise.ms"

fn load() Promise[Int]:
    return promise(fn: ok(1))

fn f() Int:
    return load()
