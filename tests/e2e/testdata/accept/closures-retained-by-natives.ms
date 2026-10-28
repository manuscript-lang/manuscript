import expect_equal from "@std/test.ms"

type Box:
    f: fn() String

fn churn(n: Int) Int:
    var t = 0

    for i in 0..n:
        let z = "junk{i}" + "padding padding padding"
        t += z.length()

    return t

fn dflt(o: Optional[fn() String], s: String) fn() String:
    return o.get(fn: s + "d")

fn mk(o: Optional[fn() String], s: String) Box:
    let h = o.get(fn: s + "x")
    return Box(f: h)

fn mk2(m: Map[Int, fn() String], s: String) List[fn() String]:
    var out = List[fn() String]()
    out.append(m.get(7).get(fn: s + "y"))
    return out

fn inc(x: Int) Int: x + 1

fn build(r: fn(Int) Int) List[fn(Int) Int]:
    var out = List[fn(Int) Int]()
    [1, 2, 3].for_each(fn i: out.append(r))
    return out

test "closures kept by natives own their captures":
    let n: Optional[fn() String] = none
    try expect_equal(dflt(n, "a")(), "ad")

    let b = mk(n, "hello" + "world")
    let c = churn(100)
    let m = Map[Int, fn() String]()
    let l = mk2(m, "abc" + "def")
    let c2 = churn(100)
    try expect_equal(b.f() + l[0](), "helloworldxabcdefy")
    try expect_equal(c + c2 > 0, true)

    let fs = build(inc)
    try expect_equal(fs.length(), 3)
    try expect_equal(fs[2](1), 2)

fn keep(r: fn(Int) Int) List[fn(Int) Int]:
    var out = List[fn(Int) Int]()
    out.append(r)
    return out

test "an escaping closure copies a captured value that is used again":
    var a = [1, 2, 3]
    let b = keep(fn x: x + a.length())
    a.append(4)
    try expect_equal(b[0](1), 4)
    try expect_equal(a.length(), 4)
