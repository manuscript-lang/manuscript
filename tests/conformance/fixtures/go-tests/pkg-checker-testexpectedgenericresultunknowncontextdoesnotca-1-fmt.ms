# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:74 TestExpectedGenericResultUnknownContextDoesNotCascade
import {TextError} from "@std/errors.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn first() Result[Int, Missing]: fail("empty")
