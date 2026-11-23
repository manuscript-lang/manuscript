// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn f[T](value: T?) T: return value or panic("called Optional.get() on null")

fn call() Void: value := f(null)
