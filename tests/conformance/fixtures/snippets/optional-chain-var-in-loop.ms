# conform: tags=generics,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"
type C:
    n: Int
impl C:
    var fn bump() Int:
        self.n += 1
        return self.n
fn main2() Unit:
    for i in 0..2:
        var o: C? = C(i)
        let v = o?.bump()
        stdout().write("{v.get(0)}\n").get()
export fn main() Int:
    main2()
    return 0
