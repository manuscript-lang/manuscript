# conform: tags=scope-cleanup,records,interfaces,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io/io.ms"
import Closeable, TextError from "@std/core.ms"

# Each resource closes exactly once, whichever owner holds it when its scope ends.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

type Pair:
    door: Door

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

fn doors() Map[String, Door]:
    var m: Map[String, Door] = {}
    m.add("a", Door("map-a"))
    return m

fn open(n: String) Door!TextError:
    return ok(Door(n))

fn collect() List[Door]!TextError:
    var found = List[Door]()
    let first = open("try-move")
    found.append(try first)

    let second = open("try-read")
    say("read {(try second).name}")
    return ok(found)

export fn main() Int:
    let count = doors().length()
    say("--result")

    let opened = open("result").is_ok()
    say("--try")

    let found = collect().get()
    say("--closeable")

    let _held: Closeable = Door("closeable")
    let many: List[Closeable] = [Door("list")]
    say("--map of records")

    var pairs: Map[String, Pair] = {}
    pairs.add("p", Pair(Door("pair")))
    say("end {count} {opened} {found.length()} {many.length()} {pairs.length()}")
    return 0
