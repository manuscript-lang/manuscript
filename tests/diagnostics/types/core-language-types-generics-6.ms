// conform: tags=diagnostics,formatter,generics,modules,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/generics.md:103

fn fail[T](message String) Result[T, Error] => error(Error(message))

fn first() Result[Int, Error] => fail("empty")  // T = Int

failed Result[Int, Error] := fail("empty")
// expect-error: MS3070 9:30 a constant takes literals, operators, collections, and other constants; compute this value in a function
