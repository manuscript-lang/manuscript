// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
test "never execute":
    return panic("check executed code")
