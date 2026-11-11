// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

fn run() Int:
    boom := fn(value: Int) Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()
