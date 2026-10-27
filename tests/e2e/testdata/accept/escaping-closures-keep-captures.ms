from "@std/test.ms" import expect_equal

type Box:
    f: Callable[[], Int]

interface Sink:
    var def put(f: Callable[[], Int]) -> Unit
    def total() -> Int

type ListSink:
    fs: List[Callable[[], Int]]

impl Sink for ListSink:
    var def put(f: Callable[[], Int]) -> Unit:
        self.fs.append(f)

    def total() -> Int:
        var t = 0
        for f in self.fs:
            t += f()
        return t

def mk(f: Callable[[], Int]) -> Box:
    return Box(f: f)

def c1(text: String) -> Int:
    var out: List[Box] = []
    for p in text.split(","):
        out.append(mk(lambda () -> Int: return p.length()))

    var t = 0
    for b in out:
        t += b.f()
    return t

def c2(text: String) -> Int:
    var m: Map[Int, Callable[[], Int]] = {}
    var i = 0

    for p in text.split(","):
        m[i] = lambda () -> Int: return p.length()
        i += 1

    var t = 0
    for k in m.keys():
        t += m.get(k).get()()
    return t

def c3(text: String) -> Int:
    var g: Callable[[], Int] = lambda () -> Int: 0
    for p in text.split(","):
        g = lambda () -> Int: return p.length()
    return g()

def c4(text: String) -> Int:
    var b = Box(f: lambda () -> Int: 0)
    for p in text.split(","):
        b.f = lambda () -> Int: return p.length()
    return b.f()

def c5(text: String) -> Int:
    var sink: Sink = ListSink(fs: [])
    for p in text.split(","):
        sink.put(lambda () -> Int: return p.length())
    return sink.total()

def outer(text: String) -> Callable[[], Int]:
    var held = text.split(",").length()
    let inner = lambda () -> Int: return held + text.length()
    return lambda () -> Int: return inner()

def c6(text: String) -> Int:
    return outer(text)()

def c7(text: String) -> Int:
    var fs: List[Callable[[], Int]] = []

    for p in text.split(","):
        let f = lambda () -> Int: return p.length()
        fs.append(f)

    var t = 0
    for f in fs:
        t += f()
    return t

def maker(text: String) -> Callable[[], Callable[[], Int]]:
    return lambda () -> Callable[[], Int]:
        let n = text.length()
        return lambda () -> Int: return n + n

def c8(text: String) -> Int:
    return maker(text)()()

def c9(text: String) -> Optional[Callable[[], Int]]:
    var r: Optional[Callable[[], Int]] = none
    for p in text.split(","):
        r = some(lambda () -> Int: return p.length())
    return r

test "closures that outlive their statement keep what they captured":
    try expect_equal(c1("x,yyyy,zz"), 7)
    try expect_equal(c2("x,yyyy,zz"), 7)
    try expect_equal(c3("x,yyyy,zz"), 2)
    try expect_equal(c4("x,yyyy,zz"), 2)
    try expect_equal(c5("x,yyyy,zz"), 7)
    try expect_equal(c6("a,b"), 5)
    try expect_equal(c7("x,yyyy,zz"), 7)
    try expect_equal(c8("abc"), 6)
    try expect_equal(c9("x,yyyy,zz").get()(), 2)
