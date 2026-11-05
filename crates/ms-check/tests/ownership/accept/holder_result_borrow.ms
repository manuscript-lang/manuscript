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
    let _holder = Holder(Gate(1))
    return source

export fn main() Int:
    let original: String! = error(Error("body", kind: "EBODY"))
    let returned = relay(original)
    print(returned.err().kind.get(""))
    print(original.err().kind.get(""))
    return 0
