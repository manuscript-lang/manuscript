// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "bad":
    if not ("\q" == ""):
        return panic(message: "check failed")
