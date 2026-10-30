# conform: tags=scope-cleanup,records,interfaces,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io.ms"
import Closeable from "@std/core.ms"

# A temporary holding a resource that is only read closes it once, at the end of its statement.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit:
        stdout().write("closed {self.name}\n").get()

interface Labeled:
    fn label() String

impl Labeled for Door:
    fn label() String:
        return self.name.clone()

type Pair:
    a: Door
    b: Door

fn maybe(n: String) Optional[Door]:
    return some(Door(n))

fn doors() List[Door]:
    return [Door("l1"), Door("l2")]

fn pair() Pair:
    return Pair(Door("pa"), Door("pb"))

fn show(l: Labeled) String:
    return l.label()

export fn main() Int:
    let present = maybe("optional").is_some()
    stdout().write("--list\n").get()
    let second = doors()[1].label()
    stdout().write("--field\n").get()
    let first = pair().a.label()
    stdout().write("--interface\n").get()
    let shown = show(Door("converted"))
    stdout().write("end {present} {second} {first} {shown}\n").get()
    return 0
