import expect_equal from "@std/test/test.ms"

type P:
    n: Int

fn reads(p: P) Unit:
    let _ = p.n

fn apply(f: fn(var P) Unit) Int:
    var p = P(1)
    f(var p)
    return p.n

fn bump(var p: P) Unit:
    p.n += 1

test "readers stand in for var functions":
    try expect_equal(apply(fn p: let _ = p.n), 1)
    try expect_equal(apply(reads), 1)

    let r = fn(p: P) Unit: let _ = p.n
    try expect_equal(apply(r), 1)
    try expect_equal(apply(fn var p: p.n += 5), 6)
    try expect_equal(apply(bump), 2)

type Holder:
    f: fn(var Int) Unit

fn run_int(f: fn(var Int) Unit) Int:
    var n = 3
    f(var n)
    return n

fn run_str(f: fn(var String) Unit) String:
    var s = "ab"
    f(var s)
    return s

fn make() fn(var Int) Unit:
    return fn(n: Int) Unit: let _ = n

test "scalars, strings, fields and returns":
    try expect_equal(run_int(fn n: let _ = n), 3)
    try expect_equal(run_str(fn s: let _ = s.length()), "ab")

    let h = Holder(fn(n: Int) Unit: let _ = n)
    try expect_equal(run_int(h.f), 3)
    try expect_equal(run_int(make()), 3)

    let g: fn(var Int) Unit = fn(n: Int) Unit: let _ = n
    try expect_equal(run_int(g), 3)

fn each_len[T](xs: List[T], f: fn(var T) Unit) Int:
    return xs.length()

test "generic callee":
    try expect_equal(each_len([1, 2], fn n: let _ = n), 2)
