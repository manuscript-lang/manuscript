import stdout from "@std/io/io.ms"
import monotonic, Instant from "@std/os/time.ms"

// ns per interface call. One line per case: `name ns checksum`.

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn report(name: String, n: Int, start: Instant, sum: Int) Unit:
    let ns = monotonic().difference(start).to_nanoseconds()
    say("{name} {ns.to_float() / n.to_float()} {sum}\n")

interface Step:
    fn apply(x: Int) Int

type AddOne:
    unused: Int

impl Step for AddOne:
    fn apply(x: Int) Int:
        return x + 1

type Scale:
    k: Int

impl Step for Scale:
    fn apply(x: Int) Int:
        return x * self.k + 1

fn make_add() Step:
    return AddOne(unused: 0)

fn make_scale(k: Int) Step:
    return Scale(k: k)

fn run_through(s: Step, n: Int) Int:
    var total = 0
    for i in 0..n:
        total += s.apply(i)
    return total

fn run_direct_add(n: Int) Int:
    var total = 0
    for i in 0..n:
        total += i + 1
    return total

export fn main() Int:
    let n = 50000000
    var start = monotonic()
    let a = run_direct_add(n)
    report("direct", n, start, a)

    // The value is built where it is called.
    start = monotonic()

    let s1: Step = AddOne(unused: 0)
    var t1 = 0
    for i in 0..n:
        t1 += s1.apply(i)
    report("iface-local", n, start, t1)

    // Built by a callee that inlines into the caller.
    start = monotonic()

    let s2 = make_add()
    var t2 = 0
    for i in 0..n:
        t2 += s2.apply(i)
    report("iface-returned", n, start, t2)

    // Passed to a function that makes the calls.
    start = monotonic()

    let t3 = run_through(make_scale(3), n)
    report("iface-param", n, start, t3)
    return 0
