import promise from "@std/concurrency/promise.ms"

fn f() Int!:
    var seen: List[Int] = []
    let p = promise(fn:  # error: concurrent code never changes a shared value, and this promise changes `seen`
        seen.append(1)
        return ok(1)
    )
    return p.wait()
