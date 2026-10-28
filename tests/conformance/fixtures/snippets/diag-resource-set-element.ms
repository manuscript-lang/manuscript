# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
from "@std/core.ms" import Closeable
type Door:
    name: String
impl Closeable for Door:
    var def close() -> Unit: return
export def main() -> Int:
    let s = Set[Door]()
    return 0
