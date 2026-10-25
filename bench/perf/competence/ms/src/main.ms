from "@std/io.ms" import stdout
from "@std/time.ms" import clock
from "@std/string.ms" import StringBuilder
from "@std/math.ms" import parse_int

interface Shape:
    def area() -> Int

type Sq:
    s: Int

type Rect:
    w: Int
    h: Int

type Tri:
    b: Int
    h: Int

impl Shape for Sq:
    def area() -> Int:
        return self.s * self.s

impl Shape for Rect:
    def area() -> Int:
        return self.w * self.h

impl Shape for Tri:
    def area() -> Int:
        return self.b * self.h / 2

type Item:
    key: Int
    name: String

type Fail:
    code: Int

impl Error for Fail:
    def message() -> String:
        return "fail"

type P:
    x: Int
    y: Int
    vx: Int
    vy: Int

def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

def fib(n: Int) -> Int:
    if n < 2:
        return n

    return fib(n - 1) + fib(n - 2)

def dispatch(n: Int) -> Int:
    let shapes: List[Shape] = [Sq(3), Rect(2, 5), Tri(4, 6), Sq(7)]
    var total = 0
    var i = 0

    while i < n:
        total += shapes.get(i % 4).area()
        i += 1

    return total

def compare(left: Int, right: Int) -> Int:
    if left < right: return -1
    if left > right: return 1

    return 0

def sorting(n: Int) -> Int:
    var v: List[Int] = []
    var i = 0

    while i < n:
        v.append(i * 7919 % 1000003)
        i += 1

    let s = v.sorted(compare)
    return s.get(0) + s.get(n / 2) + s.get(n - 1)

def closures(n: Int) -> Int:
    let base = 3
    let f = lambda (x: Int) -> Int:
        return x * base + 1
    var total = 0
    var i = 0

    while i < n:
        total += f(i)
        i += 1

    return total

def text_build_parse(n: Int) -> Int:
    var b = StringBuilder()
    var i = 0

    while i < n:
        b.append(f"{i * 31 % 1000},")
        i += 1

    let parts = b.freeze().split(",")
    var total = 0
    for p in parts:
        total += p.parse_int().get(0)
    return total

def word_map(n: Int) -> Int:
    var words: List[String] = []
    var i = 0

    while i < 1000:
        words.append(f"word{i}")
        i += 1

    var m = Map[String, Int]()
    var j = 0

    while j < n:
        let w = words.get(j * 7 % 1000)
        m.add(w.clone(), m.get(w).get(0) + 1)
        j += 1

    return m.length() + m.get("word7").get(0)

def check(i: Int) -> Result[Int, Fail]:
    if i % 1000 == 999:
        return error(Fail(i))

    return ok(i)

def step(i: Int) -> Result[Int, Fail]:
    let v = try check(i)
    return ok(v + 1)

def errors(n: Int) -> Int:
    var total = 0
    var i = 0

    while i < n:
        if let v = step(i):
            total += v
        else:
            total += 7

        i += 1

    return total

def records(n: Int) -> Int:
    var items: List[Item] = []
    var i = 0

    while i < n:
        items.append(Item(i * 7919 % 10007, f"n{i % 100}"))
        i += 1

    var total = 0
    var r = 0

    while r < 20:
        for it in items:
            total += it.key + it.name.length()
        r += 1

    return total

def grid2d(n: Int) -> Int:
    var g: List[List[Int]] = []
    var i = 0

    while i < n:
        var row: List[Int] = []
        var j = 0

        while j < n:
            row.append(i * j % 10)
            j += 1

        g.append(row)
        i += 1

    var total = 0
    var r = 0

    while r < 20:
        var a = 1

        while a < n - 1:
            var b = 1

            while b < n - 1:
                total += g.get(a).get(b) + g.get(a - 1).get(b) + g.get(a + 1).get(b)
                b += 1

            a += 1

        r += 1

    return total

def bump(p: P) -> P:
    return P(p.x + p.vx, p.y + p.vy, p.vx, p.vy)

def structs(n: Int) -> Int:
    var p = P(0, 0, 1, 2)
    var i = 0

    while i < n:
        p = bump(p)
        i += 1

    return p.x + p.y

def stack_ops(n: Int) -> Int:
    var s: List[Int] = []
    var total = 0
    var i = 0

    while i < n:
        s.append(i)

        if i % 3 == 2:
            total += s.pop().get(0)
            total += s.pop().get(0)

        i += 1

    return total + s.length()

def optionals(n: Int) -> Int:
    var total = 0
    var i = 0

    while i < n:
        var o: Optional[Int] = none
        if i % 5 != 0:
            o = some(i)

        if let v = o:
            total += v
        else:
            total += 1

        i += 1

    return total

def sets(n: Int) -> Int:
    var s = Set[Int]()
    var i = 0

    while i < n:
        s.add(i * 7919 % 100003)
        i += 1

    var hits = 0
    var j = 0

    while j < n:
        if s.contains(j):
            hits += 1
        j += 1

    return hits + s.length()

def chars(n: Int) -> Int:
    var text = "the quick brown fox jumps over the lazy dog "
    var total = 0
    var r = 0

    while r < n:
        for c in text.chars():
            if c == "o":
                total += 1
        r += 1

    return total

def timed(name: String, run: Callable[[], Int]) -> Unit:
    let t = clock().now()
    let r = run()
    say(f"{name} {clock().now().difference(t).to_nanoseconds() / 1000} {r}\n")

export def main() -> Int:
    timed("call_fib_36", lambda () -> Int: return fib(36))
    timed("dispatch_100M", lambda () -> Int: return dispatch(100000000))
    timed("closure_100M", lambda () -> Int: return closures(100000000))
    timed("sort_1M", lambda () -> Int: return sorting(1000000))
    timed("text_1M", lambda () -> Int: return text_build_parse(1000000))
    timed("strmap_10M", lambda () -> Int: return word_map(10000000))
    timed("errors_50M", lambda () -> Int: return errors(50000000))
    timed("records_1M_x20", lambda () -> Int: return records(1000000))
    timed("grid2d_500x20", lambda () -> Int: return grid2d(500))
    timed("struct_100M", lambda () -> Int: return structs(100000000))
    timed("stack_20M", lambda () -> Int: return stack_ops(20000000))
    timed("optional_100M", lambda () -> Int: return optionals(100000000))
    timed("set_2M", lambda () -> Int: return sets(2000000))
    timed("chars_1M", lambda () -> Int: return chars(1000000))
    return 0
