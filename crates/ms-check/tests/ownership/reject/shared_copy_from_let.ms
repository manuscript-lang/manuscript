import Shared from "@std/concurrency/shared.ms"

type Counter:
    n: Shared[Int]

fn bump(var c: Counter) Unit:
    c.n += 1

fn from_param(c: Counter) Unit:
    var d = c  # error: cannot copy
    bump(var d)

fn from_clone(c: Counter) Counter:
    return c.clone()  # error: cannot copy

fn from_field(c: Counter) Shared[Int]:
    return c.n  # error: cannot copy

fn from_let() Int:
    let a = Shared(0)
    let b = a  # error: cannot copy
    return a + b

fn captured_from_let() fn() Unit:
    let c = Counter(n: Shared(0))
    return fn: bump(var c)  # error: from a binding that only reads it
