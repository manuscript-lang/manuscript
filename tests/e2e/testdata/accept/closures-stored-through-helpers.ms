import expect_equal from "@std/test.ms"

fn store(var fs: List[fn() Int], f: fn() Int) Unit:
    fs.append(f)

fn relay(var fs: List[fn() Int], f: fn() Int) Unit:
    store(var fs, f)

fn deep(var fs: List[fn() Int], f: fn() Int, n: Int) Unit:
    if n == 0:
        relay(var fs, f)
        return

    deep(var fs, f, n - 1)

fn keep[T](var xs: List[T], x: T) Unit:
    xs.append(x)

fn sum(fs: List[fn() Int]) Int:
    var t = 0
    for f in fs:
        t += f()
    return t

fn d1(text: String) Int:
    var fs: List[fn() Int] = []
    for p in text.split(","):
        relay(var fs, fn() Int: return p.length())
    return sum(fs)

fn d2(text: String) Int:
    var fs: List[fn() Int] = []
    for p in text.split(","):
        deep(var fs, fn() Int: return p.length(), 3)
    return sum(fs)

fn d3(text: String) Int:
    var fs: List[fn() Int] = []
    for p in text.split(","):
        keep(var fs, fn() Int: return p.length())
    return sum(fs)

fn d4(text: String) Int:
    var fs: List[fn() Int] = []
    var i = 0

    for p in text.split(","):
        let n = p.length()
        let g = fn() Int: return n + i
        relay(var fs, g)
        i += 1

    return sum(fs)

fn d5(text: String) Int:
    var fs: List[fn() Int] = []

    for p in text.split(","):
        let g = fn() Int: return p.length()
        let h = fn() Int: return g() + 1
        relay(var fs, h)

    return sum(fs)

test "a closure stored through helper functions owns its captures":
    try expect_equal(d1("x,yyyy,zz"), 7)
    try expect_equal(d2("x,yyyy,zz"), 7)
    try expect_equal(d3("x,yyyy,zz"), 7)
    try expect_equal(d4("x,yyyy,zz"), 10)
    try expect_equal(d5("x,yyyy,zz"), 10)
