# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:73 TestReturnOnlyTypeParameterExplicitSpecialization
import TextError from "@std/core.ms"

fn fail[T](message: String) T!TextError: error(TextError(message))

fn first() Int!TextError: fail[Int]("empty")
