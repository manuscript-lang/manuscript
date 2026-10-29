import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit:
        return unit

# Methods that return an owned collection or element built from the receiver's elements copy them.
fn main() Int:
    let xs = [Res("a"), Res("b")]
    let doubled = xs.concat(xs)  # error: would copy the resources
    let first = xs.take(1)  # error: would copy the resources
    let back = xs.reversed()  # error: would copy the resources
    let kept = xs.filter(fn r: true)  # error: would copy the resources
    let found = xs.find(fn r: true)  # error: would copy the resources
    let part = xs.slice(0, 1)  # error: would copy the resources
    return doubled.length() + first.length() + back.length() + kept.length()
