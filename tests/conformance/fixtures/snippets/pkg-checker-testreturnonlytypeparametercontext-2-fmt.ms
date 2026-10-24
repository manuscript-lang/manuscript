# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:29 TestReturnOnlyTypeParameterContext
from "@std/core.ms" import TextError

def fail[T](message: String) -> Result[T, TextError]: error(TextError(message))

def first() -> Result[Int, TextError]: ...
