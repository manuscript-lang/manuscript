from "@std/test.ms" import expect_equal

def store(var fs: List[Callable[[], Int]], f: Callable[[], Int]) -> Unit:
    fs.append(f)

def relay(var fs: List[Callable[[], Int]], f: Callable[[], Int]) -> Unit:
    store(var fs, f)

def deep(var fs: List[Callable[[], Int]], f: Callable[[], Int], n: Int) -> Unit:
    if n == 0:
        relay(var fs, f)
        return

    deep(var fs, f, n - 1)

def keep[T](var xs: List[T], x: T) -> Unit:
    xs.append(x)

def sum(fs: List[Callable[[], Int]]) -> Int:
    var t = 0
    for f in fs:
        t += f()
    return t

def d1(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []
    for p in text.split(","):
        relay(var fs, lambda () -> Int: return p.length())
    return sum(fs)

def d2(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []
    for p in text.split(","):
        deep(var fs, lambda () -> Int: return p.length(), 3)
    return sum(fs)

def d3(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []
    for p in text.split(","):
        keep(var fs, lambda () -> Int: return p.length())
    return sum(fs)

def d4(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []
    var i = 0

    for p in text.split(","):
        let n = p.length()
        let g = lambda () -> Int: return n + i
        relay(var fs, g)
        i += 1

    return sum(fs)

def d5(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []

    for p in text.split(","):
        let g = lambda () -> Int: return p.length()
        let h = lambda () -> Int: return g() + 1
        relay(var fs, h)

    return sum(fs)

test "a closure stored through helper functions owns its captures":
    try expect_equal(d1("x,yyyy,zz"), 7)
    try expect_equal(d2("x,yyyy,zz"), 7)
    try expect_equal(d3("x,yyyy,zz"), 7)
    try expect_equal(d4("x,yyyy,zz"), 10)
    try expect_equal(d5("x,yyyy,zz"), 10)
