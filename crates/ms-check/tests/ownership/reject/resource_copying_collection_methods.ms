import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit:
        return unit

# Methods that return an owned collection or element built from the receiver's elements copy them.
fn main() Int:
    let xs = [Res("a"), Res("b")]
    let doubled = xs.concat(xs)  # error: concat requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    let first = xs.take(1)  # error: take requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    let back = xs.reversed()  # error: reversed requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    let kept = xs.filter(fn r: true)  # error: filter requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    let found = xs.find(fn r: true)  # error: find requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    let part = xs.slice(0, 1)  # error: slice requires Res to be Clonable; Res does not satisfy Clonable; it is or holds a Closeable resource
    return doubled.length() + first.length() + back.length() + kept.length()
