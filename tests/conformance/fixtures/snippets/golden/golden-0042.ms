// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "arithmetic":
    if not (2 + 3 == 5):
        return panic(message: "arithmetic failed")
