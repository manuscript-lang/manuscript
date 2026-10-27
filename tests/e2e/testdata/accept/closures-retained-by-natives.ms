from "@std/test.ms" import expect_equal

type Box:
    f: Callable[[], String]

def churn(n: Int) -> Int:
    var t = 0

    for i in 0..n:
        let z = f"junk{i}" + "padding padding padding"
        t += z.length()

    return t

def dflt(o: Optional[Callable[[], String]], s: String) -> Callable[[], String]:
    return o.get(lambda: s + "d")

def mk(o: Optional[Callable[[], String]], s: String) -> Box:
    let h = o.get(lambda: s + "x")
    return Box(f: h)

def mk2(m: Map[Int, Callable[[], String]], s: String) -> List[Callable[[], String]]:
    var out = List[Callable[[], String]]()
    out.append(m.get(7).get(lambda: s + "y"))
    return out

def inc(x: Int) -> Int: x + 1

def build(r: Callable[[Int], Int]) -> List[Callable[[Int], Int]]:
    var out = List[Callable[[Int], Int]]()
    [1, 2, 3].for_each(lambda i: out.append(r))
    return out

test "closures kept by natives own their captures":
    let n: Optional[Callable[[], String]] = none
    try expect_equal(dflt(n, "a")(), "ad")

    let b = mk(n, "hello" + "world")
    let c = churn(100)
    let m = Map[Int, Callable[[], String]]()
    let l = mk2(m, "abc" + "def")
    let c2 = churn(100)
    try expect_equal(b.f() + l[0](), "helloworldxabcdefy")
    try expect_equal(c + c2 > 0, True)

    let fs = build(inc)
    try expect_equal(fs.length(), 3)
    try expect_equal(fs[2](1), 2)

def keep(r: Callable[[Int], Int]) -> List[Callable[[Int], Int]]:
    var out = List[Callable[[Int], Int]]()
    out.append(r)
    return out

test "an escaping closure copies a captured value that is used again":
    var a = [1, 2, 3]
    let b = keep(lambda x: x + a.length())
    a.append(4)
    try expect_equal(b[0](1), 4)
    try expect_equal(a.length(), 4)
