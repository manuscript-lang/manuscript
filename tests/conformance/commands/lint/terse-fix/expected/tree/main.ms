import print from "@std/core.ms"
import Bytes from "@std/bytes.ms"

fn empties(xs: List[Int], m: Map[String, Int], text: String) Bool:
    if xs.is_empty():
        return true
    if not m.is_empty():
        return false
    return text.is_empty()

fn first(xs: List[Int]) Int:
    return xs[0]

fn counts(var m: Map[String, Int], k: String) Void:
    var total = 0
    total = m.get_or(k, 0)
    m[k] += 1
    print(total)

fn pick(flag: Bool) Int:
    return if flag: 2 else: 1

fn done(n: Int) Int:
    return n + 1

fn loop(xs: List[Int]) Int:
    var sum = 0
    for i in 0..10:
        sum += i
    for j in 0..xs.length():
        sum += xs[j]
    var out: List[Int] = []
    for x in xs:
        out.append(x)
    return sum

fn sorted(var xs: List[Int]) Void:
    ys := xs.sort()
    print(xs.reverse())
    print(ys)

fn nothing() Void!:
    print("x")

fn bytes_text(b: Bytes) String:
    return b.to_string()

fn parse(text: String) Int!:
    return ok(1)

fn unit() Void!:
    return ok()

fn slices(xs: List[Int]) List[Int]:
    return xs.slice(1, 3).get_or([]).clone()

fn run() Void!:
    r := parse("1")
    r.get()
    void unit()
    print(parse("2"))
    print(parse("3").get())

fn main() Void:
    print(empties([], {}, ""))
    print(slices([1]))
