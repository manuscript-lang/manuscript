// conform: tags=scope-cleanup,records,interfaces,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A temporary holding a resource that is only read closes it once, at the end of its statement.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")
        return ok(unit)

interface Labeled:
    fn label() String

impl Labeled for Door:
    fn label() String:
        return self.name.clone()

type Pair:
    a: Door
    b: Door

fn maybe(n: String) Door?:
    return Door(n)

fn doors() List[Door]:
    return [Door("l1"), Door("l2")]

fn pair() Pair:
    return Pair(Door("pa"), Door("pb"))

fn show(l: Labeled) String:
    return l.label()

export fn main() Int:
    present := maybe("optional").is_some()
    print("--list")

    second := doors()[1].label()
    print("--field")

    first := pair().a.label()
    print("--interface")

    shown := show(Door("converted"))
    print("end {present} {second} {first} {shown}")
    return 0
