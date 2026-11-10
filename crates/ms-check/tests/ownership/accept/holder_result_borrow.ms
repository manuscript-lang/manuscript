import Closeable from "@std/core.ms"

type Gate:
    id: Int

impl Closeable for Gate:
    var fn close() Unit!:
        print("close {self.id}")
        return ok(unit)

type Holder:
    gate: Gate

fn relay[T](source: T!) T!:
    gate := Gate(1)
    _holder := Holder(gate)
    return source

export fn main() Int:
    original: String! = error(Error("body", kind: "EBODY"))
    returned := relay(original)
    print(returned.err().kind.get(""))
    print(original.err().kind.get(""))
    return 0
