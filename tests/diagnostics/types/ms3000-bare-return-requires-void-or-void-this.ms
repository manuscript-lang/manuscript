// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn number(value Int?) Int => return value or panic("called Optional.get() on null")

fn call() Int => return
// expect-error: MS3000 7:18 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
