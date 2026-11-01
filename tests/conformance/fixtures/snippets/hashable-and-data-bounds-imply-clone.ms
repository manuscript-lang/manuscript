# conform: tags=generics,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

type Box[T]:
    v: T

fn a[T: Clonable](xs: List[Box[T]]) List[Box[T]]: xs.concat(xs)

fn b[T: Clonable](xs: List[T]) List[T]: xs.take(1)

fn c[T: Clonable](xs: List[T]) T?: xs.first().map(fn x: x.clone())

fn d[T](xs: List[T]) Int: xs.length()

fn e[T: Clonable](m: Map[String, T]) Map[String, T]: m.clone()

fn f[T: Clonable](xs: List[T]) List[T]: xs.slice(0, 1).get([])

fn g[T: Hashable](xs: List[T]) Set[T]:
    var s = Set[T]()
    for x in xs:
        s.add(x.clone())
    return s

fn h[T: Comparable & Clonable](xs: List[T]) List[T]: xs.sorted()

export fn main() Int:
    let l = a([Box(1), Box(2)])
    let s = g(["a", "b", "a"])
    let t = h([3, 1, 2])
    (
        stdout()
        .write(
            "{l.length()} {b([5, 6]).length()} {d(l)} {s.length()} {t[0]} {f([7, 8]).length()}\n"
        )
        .get()
    )
    return 0
