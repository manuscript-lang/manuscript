# conform: tags=diagnostics,generics,modules,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:103
from "@std/core.ms" import TextError

def fail[T](message: String) -> Result[T, TextError]: error(TextError(message))

def first() -> Result[Int, TextError]: fail("empty")  # T = Int

let failed: Result[Int, TextError] = fail("empty")
