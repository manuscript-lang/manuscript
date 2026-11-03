import promise, wait_all from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn f() List[Int]!:
    let xs = [1, 2, 3]
    let a = promise(fn: total(xs))
    let b = promise(fn: total(xs))
    return wait_all([a, b])

fn local_state() Int!:
    let p = promise(fn:
        var seen: List[Int] = []
        seen.append(1)
        return ok(seen.length())
    )
    return p.wait()

fn changed_after_scope() Int!:
    var xs = [1, 2, 3]
    let first = total(xs)
    if true:
        let p = promise(fn: total(xs))
        let n = try p.wait()
        return ok(n)
    xs.append(4)
    return first

fn changed_after_handoff() List[Int]!:
    var xs = [1, 2, 3]
    let all = try wait_all([promise(fn: total(xs)), promise(fn: total(xs))])
    xs.append(4)
    return ok(all)
