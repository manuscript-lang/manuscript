# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:73 TestReturnOnlyTypeParameterExplicitSpecialization
import {TextError} from "@std/core.ms"

fn fail[T](message: String) Result[T, TextError]: error(TextError(message))

fn first() Result[Int, TextError]: fail[Int]("empty")
