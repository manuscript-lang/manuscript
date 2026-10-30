import expect_equal from "@std/test.ms"

type Box:
    f: fn() Int

interface Sink:
    var fn put(f: fn() Int) Unit
    fn total() Int

type ListSink:
    fs: List[fn() Int]

impl Sink for ListSink:
    var fn put(f: fn() Int) Unit:
        self.fs.append(f)

    fn total() Int:
        var t = 0
        for f in self.fs:
            t += f()
        return t

fn mk(f: fn() Int) Box:
    return Box(f: f)

fn c1(text: String) Int:
    var out: List[Box] = []
    for p in text.split(","):
        out.append(mk(fn() Int: return p.length()))

    var t = 0
    for b in out:
        t += b.f()
    return t

fn c2(text: String) Int:
    var m: Map[Int, fn() Int] = {}
    var i = 0

    for p in text.split(","):
        m[i] = fn() Int: return p.length()
        i += 1

    var t = 0
    for k in m.keys():
        t += m.get(k).get()()
    return t

fn c3(text: String) Int:
    var g: fn() Int = fn() Int: 0
    for p in text.split(","):
        g = fn() Int: return p.length()
    return g()

fn c4(text: String) Int:
    var b = Box(f: fn() Int: 0)
    for p in text.split(","):
        b.f = fn() Int: return p.length()
    return b.f()

fn c5(text: String) Int:
    var sink: Sink = ListSink(fs: [])
    for p in text.split(","):
        sink.put(fn() Int: return p.length())
    return sink.total()

fn outer(text: String) fn() Int:
    var held = text.split(",").length()
    let inner = fn() Int: return held + text.length()
    return fn() Int: return inner()

fn c6(text: String) Int:
    return outer(text)()

fn c7(text: String) Int:
    var fs: List[fn() Int] = []

    for p in text.split(","):
        let f = fn() Int: return p.length()
        fs.append(f)

    var t = 0
    for f in fs:
        t += f()
    return t

fn maker(text: String) fn() fn() Int:
    return fn() fn() Int:
        let n = text.length()
        return fn() Int: return n + n

fn c8(text: String) Int:
    return maker(text)()()

fn c9(text: String)(fn() Int)?:
    var r: (fn() Int)? = none
    for p in text.split(","):
        r = some(fn() Int: return p.length())
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
