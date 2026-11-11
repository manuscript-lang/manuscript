// conform: tags=diagnostics
// conform: phase=check
import sleep, nanoseconds from "@std/time.ms"

test "timeout":
    sleep(nanoseconds(1000000000))

test "after":
    return unit
