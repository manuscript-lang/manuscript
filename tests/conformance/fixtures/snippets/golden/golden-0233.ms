// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
fn f() Int:
    panic = 2
    return 0
