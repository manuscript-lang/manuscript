// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "list":
    values := [1, 2]
    if not (values.length() == 2):
        return panic(message: "check failed")
