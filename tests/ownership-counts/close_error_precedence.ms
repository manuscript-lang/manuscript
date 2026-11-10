// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: original body
// expect-stdout: EBODY
// expect-stdout: body
// expect-stdout: close 3
// expect-stdout: caller error
// expect-stdout: ECALLER
// expect-stdout: caller
// expect-stdout: caller error
// expect-stdout: caller
import Closeable from "@std/core.ms"

type Token:
    id: Int

impl Closeable for Token:
    var fn close() Unit!:
        print("close {self.id}")
        return error(Error("close failed", kind: "ECLOSE"))

fn owned() Int!:
    _first := Token(1)
    _second := Token(2)
    return error(Error("original body", kind: "EBODY", details: {"id": "body"}))

fn borrowed(cause: Error) Int!:
    _resource := Token(3)
    return error(cause)

export fn main() Int:
    first := owned()
    cause := first.err()
    print(cause.message)
    print(cause.kind.get(""))
    print(cause.details["id"])

    original := Error("caller error", kind: "ECALLER", details: {"id": "caller"})
    second := borrowed(original)
    returned := second.err()
    print(returned.message)
    print(returned.kind.get(""))
    print(returned.details["id"])
    print(original.message)
    print(original.details["id"])
    return 0
