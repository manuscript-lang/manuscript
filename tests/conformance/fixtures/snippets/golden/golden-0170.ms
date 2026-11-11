// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
export fn main() Int:
    return panic(message: "profile failure")
