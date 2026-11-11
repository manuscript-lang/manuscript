// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
test "several checks":
    good := 2 + 3
    if good == 5:
        panic("last check failed")
