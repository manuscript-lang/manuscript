// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
type Override:
    received: Bool
impl FileSystem for Override:
