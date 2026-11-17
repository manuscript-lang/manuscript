// conform: tags=generics,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

type C:
    n: Int

fn var C.bump() Int:
    self.n += 1
    return self.n

fn main2() Void:
    for i in 0..2:
        var o: C? = C(i)
        v := o?.bump()
        stdout().write(f"{v.get_or(0)}\n").get()

fn main() Void:
    main2()
