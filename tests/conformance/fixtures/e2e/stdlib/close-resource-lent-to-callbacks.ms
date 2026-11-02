# conform: tags=scope-cleanup,closures,tier-io
# conform: phase=run
# conform: origin=value-semantics-audit
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

# A resource handed to a list or read by a callback closes exactly once.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("closed {self.name}\n").get()
        return ok(unit)

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

fn maybe(n: String) Door?:
    return Door(n)

fn open(n: String) Door!Error:
    return ok(Door(n))

export fn main() Int:
    var doors = [Door("first")]
    doors.insert(0, Door("inserted"))
    say("--map")

    let name = maybe("mapped").map(fn d: d.name.clone())
    let size = open("result").map(fn d: d.name.length())
    say("--fallback")

    let failed: Door!Error = error(Error("no"))
    let fallback = failed.get_or_else(fn cause: Door("fallback"))
    say("end {doors.length()} {name.get()} {size.get()} {fallback.name}")
    return 0
