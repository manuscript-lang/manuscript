# conform: tags=optional,mutation,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io.ms"
type Big:
    a: Int
    b: Int
    s: String
impl Big:
    var fn inc() Int:
        self.a += 1
        self.s = self.s + "x"
        return self.a
type Node:
    v: Int
    next: Node?
impl Node:
    var fn inc() Int:
        self.v += 1
        return self.v
fn main2() Unit:
    var xs: List[Int]? = [1]
    xs?.append(2)
    var b: Big? = Big(1, 2, "s")
    b?.inc()
    b?.inc()
    var n: Node? = Node(1, Node(5, none))
    n?.inc()
    n?.next?.inc()
    if let l = xs:
        stdout().write("{l.length()}\n").get()
    if let bb = b:
        stdout().write("{bb.a} {bb.s}\n").get()
    if let nn = n:
        stdout().write("{nn.v}\n").get()
        if let m = nn.next:
            stdout().write("{m.v}\n").get()
export fn main() Int:
    main2()
    return 0
