import promise from "@std/concurrency/promise.ms"

fn f() Int!:
    var count = 0
    let p = promise(fn:  # error: concurrent code never changes a shared value, and this promise changes `count`
        count += 1
        return ok(count)
    )
    return p.wait()
