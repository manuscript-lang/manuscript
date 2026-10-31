import FallibleCloseable, TextError from "@std/core.ms"

type Gate:
    fails: Bool

impl FallibleCloseable for Gate:
    var fn close() Result[Unit, Error]:
        if self.fails:
            return error(TextError("close"))

        return ok(unit)

type Holder:
    gate: Gate

fn hold() Result[Int, Error]:
    let _holder = Holder(Gate(true))
    return ok(1)

export fn main() Int:
    return 0
