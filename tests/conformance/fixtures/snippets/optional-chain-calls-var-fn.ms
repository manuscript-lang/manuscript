# conform: tags=optional,mutation,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

type C:
    n: Int
    log: List[String]

impl C:
    var fn bump() Int:
        self.n += 1
        return self.n

    var fn note(s: String) Unit:
        self.log.append(s)

    fn get() Int: self.n

type H:
    c: C?

fn show(x: Int?) Unit:
    if let v = x:
        stdout().write("some {v}\n").get()
    else:
        stdout().write("none\n").get()

fn tick(var c: C?) Int?:
    return c?.bump()

export fn main() Int:
    var c: C? = C(1, List[String]())
    var none_c: C? = none
    show(c?.bump())
    show(c?.bump())
    show(none_c?.bump())

    c?.note("hi")

    show(c?.get())
    show(c?.log.length())

    var h = H(C(10, List[String]()))
    show(h.c?.bump())
    show(h.c?.get())
    show(tick(var c))
    show(c?.get())

    var hn = H(none)
    show(hn.c?.bump())
    return 0
