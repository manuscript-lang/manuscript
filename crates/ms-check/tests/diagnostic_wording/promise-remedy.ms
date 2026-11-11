import promise from "@std/concurrency/promise.ms"
fn f() Int!:
    pending := promise(fn() Int!: ok(1))
    return pending.wait()
