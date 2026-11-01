# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "iface.is"

import category from "@std/core.ms"
import IoError from "@std/io/io.ms"

export fn main() Int:
    let cause: Error = IoError.Closed
    let _c = category(cause)
    return 0
