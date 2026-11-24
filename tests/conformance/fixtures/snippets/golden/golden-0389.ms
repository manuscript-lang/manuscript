// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn f(value Int?) Int: return value or panic("called Optional.get() on null")

fn call() Int: return f(4)
