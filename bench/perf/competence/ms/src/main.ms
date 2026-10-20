import {stdout} from "@std/io.ms"
import {clock} from "@std/time.ms"
import {StringBuilder} from "@std/string.ms"
import {parse_int} from "@std/numbers.ms"

interface Shape:
    fn area() Int

type Sq:
    s: Int

type Rect:
    w: Int
    h: Int

type Tri:
    b: Int
    h: Int

impl Shape for Sq:
    fn area() Int:
        return self.s * self.s

impl Shape for Rect:
    fn area() Int:
        return self.w * self.h

impl Shape for Tri:
    fn area() Int:
        return self.b * self.h / 2

type Item:
    key: Int
    name: String

type Fail:
    code: Int

impl Error for Fail:
    fn message() String:
        return "fail"

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn fib(n: Int) Int:
    if n < 2:
        return n

    return fib(n - 1) + fib(n - 2)

fn dispatch(n: Int) Int:
    let shapes: List[Shape] = [
        Shape(value: Sq(3)),
        Shape(value: Rect(2, 5)),
        Shape(value: Tri(4, 6)),
        Shape(value: Sq(7))
    ]
    var total = 0
    var i = 0

    while i < n:
        total += shapes.get(i % 4).area()
        i += 1

    return total

fn compare(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn sorting(n: Int) Int:
    var v: List[Int] = []
    var i = 0

    while i < n:
        v.append(i * 7919 % 1000003)
        i += 1

    let s = v.sorted(compare)
    return s.get(0) + s.get(n / 2) + s.get(n - 1)

fn closures(n: Int) Int:
    let base = 3
    let f = fn(x: Int) Int:
        return x * base + 1
    var total = 0
    var i = 0

    while i < n:
        total += f(i)
        i += 1

    return total

fn text_build_parse(n: Int) Int:
    var b = StringBuilder()
    var i = 0

    while i < n:
        b.append("{i * 31 % 1000},")
        i += 1

    let parts = b.freeze().split(",")
    var total = 0
    for p in parts:
        total += p.parse_int().get(0)
    return total

fn word_map(n: Int) Int:
    var words: List[String] = []
    var i = 0

    while i < 1000:
        words.append("word{i}")
        i += 1

    var m = Map[String, Int]()
    var j = 0

    while j < n:
        let w = words.get(j * 7 % 1000)
        m.add(w, m.get(w).get(0) + 1)
        j += 1

    return m.length() + m.get("word7").get(0)

fn check(i: Int) Result[Int, Fail]:
    if i % 1000 == 999:
        return error(Fail(i))

    return ok(i)

fn step(i: Int) Result[Int, Fail]:
    let v = try check(i)
    return ok(v + 1)

fn errors(n: Int) Int:
    var total = 0
    var i = 0

    while i < n:
        if let v = step(i):
            total += v
        else:
            total += 7

        i += 1

    return total

fn records(n: Int) Int:
    var items: List[Item] = []
    var i = 0

    while i < n:
        items.append(Item(i * 7919 % 10007, "n{i % 100}"))
        i += 1

    var total = 0
    var r = 0

    while r < 20:
        for it in items:
            total += it.key + it.name.length()
        r += 1

    return total

fn timed(name: String, run: fn() Int) Unit:
    let t = clock().now()
    let r = run()
    say("{name} {clock().now().difference(t).to_nanoseconds() / 1000} {r}\n")

export fn main() Int:
    timed("call_fib_36", fn() Int: return fib(36))
    timed("dispatch_100M", fn() Int: return dispatch(100000000))
    timed("closure_100M", fn() Int: return closures(100000000))
    timed("sort_1M", fn() Int: return sorting(1000000))
    timed("text_1M", fn() Int: return text_build_parse(1000000))
    timed("strmap_10M", fn() Int: return word_map(10000000))
    timed("errors_50M", fn() Int: return errors(50000000))
    timed("records_1M_x20", fn() Int: return records(1000000))
    return 0
