// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "text":
    if not ("{1}" == "1"):
        return panic(message: "check failed")
