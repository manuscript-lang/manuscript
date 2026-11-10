import Closeable from "@std/core.ms"

type Gate:
    id: Int

impl Closeable for Gate:
    var fn close() Unit!:
        print("close {self.id}")

type Holder:
    gate: Gate

fn relay[T](source: T!) T!:
    let gate = Gate(1)
    let _holder = Holder(gate)
    return source

fn main() Unit:
    let original: String! = error(Error("body", kind: "EBODY"))
    let returned = relay(original)
    print(returned.err().kind.get(""))
    print(original.err().kind.get(""))
