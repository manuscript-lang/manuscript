// conform: tags=optional,mutation,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

type C:
    n: Int
    log: List[String]

fn var C.bump() Int:
    self.n += 1
    return self.n

fn var C.note(s: String) Void:
    self.log.append(s)

fn C.get() Int: self.n

type H:
    c: C?

fn show(x: Int?) Void:
    if v := x:
        stdout().write(f"some {v}\n").get()
    else:
        stdout().write("none\n").get()

fn tick(var c: C?) Int?:
    return c?.bump()

fn main() Void:
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
