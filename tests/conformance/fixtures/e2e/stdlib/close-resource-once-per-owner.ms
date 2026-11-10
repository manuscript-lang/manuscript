// conform: tags=scope-cleanup,records,interfaces,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// Each resource closes exactly once, whichever owner holds it when its scope ends.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")
        return ok(unit)

type Pair:
    door: Door

fn say(s: String) Unit:
    print("{s}")

fn doors() Map[String, Door]:
    var m: Map[String, Door] = {}
    m.add("a", Door("map-a"))
    return m

fn open(n: String) Door!Error:
    return ok(Door(n))

fn collect() List[Door]!Error:
    var found = List[Door]()
    first := open("try-move")
    found.append(try first)

    second := open("try-read")
    say("read {(try second).name}")
    return ok(found)

export fn main() Int:
    count := doors().length()
    say("--result")

    opened := open("result").is_ok()
    say("--try")

    found := collect().get()
    say("--closeable")

    _held: Closeable = Door("closeable")
    many: List[Closeable] = [Door("list")]
    say("--map of records")

    var pairs: Map[String, Pair] = {}
    pairs.add("p", Pair(Door("pair")))
    say("end {count} {opened} {found.length()} {many.length()} {pairs.length()}")
    return 0
