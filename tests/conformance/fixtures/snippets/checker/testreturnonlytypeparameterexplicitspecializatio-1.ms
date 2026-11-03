# conform: tags=diagnostics,generics,modules,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:73 TestReturnOnlyTypeParameterExplicitSpecialization

fn fail[T](message: String) T!Error: error(Error(message))

fn first() Int!Error: fail[Int]("empty")
