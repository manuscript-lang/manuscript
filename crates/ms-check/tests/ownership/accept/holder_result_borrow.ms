import Closeable from "@std/core.ms"

type Gate:
    id: Int

fn move Gate.close() Void!:
    print(f"close {self.id}")

type Holder:
    gate: Gate

fn relay[T](source: T!) T!:
    gate := Gate(1)
    _holder := Holder(gate)
    return source

fn main() Void:
    original: String! := error(Error("body", kind: "EBODY"))
    returned := relay(original)
    print(returned.err().kind.get_or(""))
    print(original.err().kind.get_or(""))
