// conform: tags=optional,mutation,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

type Big:
    a: Int
    b: Int
    s: String

fn var Big.inc() Int:
    self.a += 1
    self.s = self.s + "x"
    return self.a

type Node:
    v: Int
    next: Node?

fn var Node.inc() Int:
    self.v += 1
    return self.v

fn main2() Void:
    var xs: List[Int]? = [1]
    xs?.append(2)

    var b: Big? = Big(1, 2, "s")
    b?.inc()
    b?.inc()

    var n: Node? = Node(1, Node(5, null))
    n?.inc()
    n?.next?.inc()
    if l := xs:
        stdout().write(f"{l.length()}\n").get()
    if bb := b:
        stdout().write(f"{bb.a} {bb.s}\n").get()

    if nn := n:
        stdout().write(f"{nn.v}\n").get()
        if m := nn.next:
            stdout().write(f"{m.v}\n").get()

fn main() Void:
    main2()
