from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

# Methods that return an owned collection or element built from the receiver's elements copy them.
def main() -> Int:
    let xs = [Res("a"), Res("b")]
    let doubled = xs.concat(xs)  # error: would copy the resources
    let first = xs.take(1)  # error: would copy the resources
    let back = xs.reversed()  # error: would copy the resources
    let kept = xs.filter(lambda r: True)  # error: would copy the resources
    let found = xs.find(lambda r: True)  # error: would copy the resources
    let part = xs.slice(0, 1)  # error: would copy the resources
    return doubled.length() + first.length() + back.length() + kept.length()
