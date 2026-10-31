# conform: tags=diagnostics,generics,modules,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:74 TestExpectedGenericResultUnknownContextDoesNotCascade
import TextError from "@std/core.ms"

fn fail[T](message: String) T!TextError: error(TextError(message))

fn first() Int!Missing: fail("empty")
