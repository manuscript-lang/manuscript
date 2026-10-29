# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "iface.is"
# expect-mir: "iface.new"

import stdout from "@std/io.ms"
import TextError from "@std/core.ms"

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

export fn main() Int:
    let e: Error = TextError("bad")
    let a = Key(id: 1, label: "a")
    let b = Key(id: 1, label: "b")
    let _r = stdout().write("{e} {a == b}\n")
    return 0
