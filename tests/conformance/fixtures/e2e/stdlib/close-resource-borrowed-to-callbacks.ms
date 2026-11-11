// conform: tags=scope-cleanup,closures,tier-io
// conform: phase=run
// conform: origin=value-semantics-audit
import Closeable from "@std/core.ms"

// A resource handed to a list or read by a callback closes exactly once.
type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        print("closed {self.name}")

fn say(s: String) Unit:
    print("{s}")

fn maybe(n: String) Door?:
    return Door(n)

fn open(n: String) Door!Error:
    return ok(Door(n))

fn main() Unit:
    var doors = [Door("first")]
    doors.insert(0, Door("inserted"))
    say("--map")

    name := maybe("mapped").map(fn d: d.name.clone())
    size := open("result").map(fn d: d.name.length())
    say("--fallback")

    failed: Door!Error := error(Error("no"))
    fallback := failed.get_or_else(fn cause: Door("fallback"))
    say("end {doors.length()} {name.get()} {size.get()} {fallback.name}")
