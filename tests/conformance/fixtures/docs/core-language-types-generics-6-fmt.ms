# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:103

fn fail[T](message: String) Result[T, Error]: error(Error(message))

fn first() Result[Int, Error]: fail("empty")  # T = Int

let failed: Result[Int, Error] = fail("empty")
