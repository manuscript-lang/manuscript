import promise, wait_all from "@std/concurrency/promise.ms"

fn total(xs: List[Int]) Int!:
    return ok(xs.length())

fn f() List[Int]!:
    xs := [1, 2, 3]
    a := promise(fn: total(xs))
    b := promise(fn: total(xs))
    return wait_all([a, b])

fn local_state() Int!:
    p := promise(fn:
        var seen: List[Int] = []
        seen.append(1)
        return ok(seen.length())
    )
    return p.wait()

fn changed_after_scope() Int!:
    var xs = [1, 2, 3]
    first := total(xs)
    if true:
        p := promise(fn: total(xs))
        n := try p.wait()
        return ok(n)
    xs.append(4)
    return first

fn changed_after_handoff() List[Int]!:
    var xs = [1, 2, 3]
    all := try wait_all([promise(fn: total(xs)), promise(fn: total(xs))])
    xs.append(4)
    return ok(all)
