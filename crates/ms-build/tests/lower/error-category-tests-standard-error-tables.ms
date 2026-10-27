# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "iface.is"

from "@std/core.ms" import category
from "@std/io.ms" import IoError

export def main() -> Int:
    let cause: Error = IoError.Closed
    let _c = category(cause)
    return 0
