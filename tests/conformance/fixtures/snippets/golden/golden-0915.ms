// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "bad":
    if not ("\u{D800}" == ""):
        return panic(message: "check failed")
