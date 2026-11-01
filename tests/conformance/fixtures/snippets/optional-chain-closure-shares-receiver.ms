# conform: tags=optional,closures,mutation,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"
type C:
    n: Int
impl C:
    var fn bump() Int:
        self.n += 1
        return self.n
    fn get() Int: self.n
fn show(x: Int?) Unit:
    stdout().write("{x.get(-1)}\n").get()
fn clos() Unit:
    var c: C? = C(1)
    let f = fn: c?.bump()
    show(f())
    show(f())
    show(c?.get())
fn twice() Unit:
    var c: C? = C(1)
    show(c?.bump())
    show(c?.bump())
    let a = c?.bump()
    show(a)
    var xs: List[C?] = [C(1), none]
    show(xs[0]?.bump())
    show(xs[1]?.bump())
    show(xs[0]?.get())
fn args() Unit:
    var c: C? = C(1)
    show(c?.bump() )
    var d: C? = C(5)
    show(d?.get() )
export fn main() Int:
    clos()
    twice()
    args()
    return 0
