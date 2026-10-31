import FallibleCloseable, TextError from "@std/core.ms"

type Gate:
    fails: Bool

impl FallibleCloseable for Gate:
    var fn close() Result[Unit, Error]:
        if self.fails:
            return error(TextError("close"))

        return ok(unit)

fn plain() Int:
    let _gate = Gate(true)
    return 1

export fn main() Int:
    return plain()
