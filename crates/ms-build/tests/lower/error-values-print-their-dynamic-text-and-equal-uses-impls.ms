# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "iface.is"
# expect-mir: "iface.new"

from "@std/io.ms" import stdout
from "@std/core.ms" import TextError

type Key:
    id: Int
    label: String

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return self.id == other.id

export def main() -> Int:
    let e: Error = TextError("bad")
    let a = Key(id: 1, label: "a")
    let b = Key(id: 1, label: "b")
    let _r = stdout().write(f"{e} {a == b}\n")
    return 0
