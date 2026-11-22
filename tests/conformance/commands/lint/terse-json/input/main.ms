import print from "@std/core.ms"
import Bytes from "@std/bytes.ms"

fn empties(xs: List[Int], m: Map[String, Int], text: String) Bool:
    if xs.length() == 0:
        return true
    if m.length() > 0:
        return false
    return text.length() == 0

fn first(xs: List[Int]) Int:
    return xs.get(0)

fn counts(var m: Map[String, Int], k: String) Void:
    var total = 0
    total = m.get(k).get_or(0)
    m[k.clone()] = m.get(k).get() + 1
    print(total)

fn pick(flag: Bool) Int:
    var x = 1
    if flag:
        x = 2
    return x

fn done(n: Int) Int:
    r := n + 1
    return r

fn loop(xs: List[Int]) Int:
    var i = 0
    var sum = 0
    while i < 10:
        sum += i
        i += 1
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
    return ok()

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
    unit().get_or(none)
    print(parse("2"))
    print(parse("3").get())
    return ok()

fn main() Void:
    print(empties([], {}, ""))
    print(slices([1]))
