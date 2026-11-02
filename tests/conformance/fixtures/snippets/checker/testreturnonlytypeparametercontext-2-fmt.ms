# conform: tags=formatter,generics,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:29 TestReturnOnlyTypeParameterContext

fn fail[T](message: String) T!Error: error(Error(message))

fn first() Int!Error: ...
