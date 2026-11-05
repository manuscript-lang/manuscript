// expect-stdout: body 42
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: false
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: true
// Scalar-backed resources still have cleanup duties while constructor fields are pending.
import Closeable from "@std/core.ms"

type Token:
    id: Int

impl Closeable for Token:
    var fn close() Unit!:
        print("close {self.id}")
        return ok(unit)

type Wrapped:
    first: Token?
    second: Token!
    code: Int

fn check(fail: Bool) Int!:
    if fail: return error(Error("field failed"))

    return ok(42)

fn build(fail: Bool) Unit!:
    let value = Wrapped(Token(1), ok(Token(2)), try check(fail))
    print("body {value.code}")
    return ok(unit)

export fn main() Int:
    print(build(false).is_error())
    print(build(true).is_error())
    return 0
