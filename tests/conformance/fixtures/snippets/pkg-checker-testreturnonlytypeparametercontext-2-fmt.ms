# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:29 TestReturnOnlyTypeParameterContext
import {TextError} from "@std/errors.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn first() Result[Int, TextError]:
    
