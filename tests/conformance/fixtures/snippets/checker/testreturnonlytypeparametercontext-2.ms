// conform: tags=diagnostics,generics,modules,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=check
// conform: origin=pkg/checker/inference_hints_test.go:29 TestReturnOnlyTypeParameterContext

fn fail[T](message String) T!Error => error(Error(message))

fn first() Int!Error { ... }
// expect-error: MS3000 7:1 reachable fallthrough in function returning Result[Int, Error]; end every path with 'return <Result[Int, Error]>' (or make the last branch return)
