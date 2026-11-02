# conform: tags=mutation,records,lists,tier-io
# conform: phase=run
# conform: origin=proposals/reference-ownership.md
# A lender that hands a temporary back whole (`id(mk(3))`) gives the caller that temporary: no copy, one owner.
import stdout from "@std/io/io.ms"
type Big:
    name: String
    items: List[Int]
fn mk(n: Int) Big:
    var xs = List[Int]()
    for i in 0..n:
        xs.append(i)
    return Big("a name that is long enough to live on the heap", xs)
fn id(b: Big) Big: b
fn pass[T](x: T) T: x
impl Big:
    fn me() Big: return self
fn first_of(b: Big) Int:
    return b.items[0]
export fn main() Int:
    let w = id(mk(3))
    let p = pass(mk(4))
    let q = id(id(mk(5)))
    let r = mk(6).me()
    let s = id(mk(7)).items.length() + first_of(id(mk(8)))
    var t = id(mk(2))
    t.items.append(9)
    stdout().write("{w.items} {p.items} {q.items} {r.items} {s} {t.items} {pass(mk(1)).items}\n").get()
    return 0
