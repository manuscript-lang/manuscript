import expect_equal from "@std/test/test.ms"

type P:
    n: Int

fn reads(p: P) Unit:
    _ := p.n

fn apply(f: fn(var P) Unit) Int:
    var p = P(1)
    f(var p)
    return p.n

fn bump(var p: P) Unit:
    p.n += 1

test "readers stand in for var functions":
    try expect_equal(apply(fn p: _ := p.n), 1)
    try expect_equal(apply(reads), 1)

    r := fn(p: P) Unit: _ := p.n
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
    return fn(n: Int) Unit: _ := n

test "scalars, strings, fields and returns":
    try expect_equal(run_int(fn n: _ := n), 3)
    try expect_equal(run_str(fn s: _ := s.length()), "ab")

    h := Holder(fn(n: Int) Unit: _ := n)
    try expect_equal(run_int(h.f), 3)
    try expect_equal(run_int(make()), 3)

    g: fn(var Int) Unit = fn(n: Int) Unit: _ := n
    try expect_equal(run_int(g), 3)

fn each_len[T](xs: List[T], f: fn(var T) Unit) Int:
    return xs.length()

test "generic callee":
    try expect_equal(each_len([1, 2], fn n: _ := n), 2)
