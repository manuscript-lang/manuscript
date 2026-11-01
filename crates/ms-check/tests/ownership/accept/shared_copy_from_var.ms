import Shared from "@std/concurrency/shared.ms"

type Counter:
    n: Shared[Int]

fn bump(var c: Counter) Unit:
    c.n += 1

fn from_var_param(var c: Counter) Counter:
    var d = c
    bump(var d)
    return c.clone()

fn hand_on() Counter:
    let fresh = Counter(n: Shared(0))
    var mine = fresh
    bump(var mine)
    return mine

fn captured_from_var() fn() Unit:
    var n = Shared(0)
    var c = Counter(n: Shared(0))
    return fn:
        n += 1
        bump(var c)

fn read_only(c: Counter) Int:
    let n: Int = c.n
    return n
