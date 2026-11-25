// conform: tags=diagnostics,formatter,generics,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/contextual_generics_test.go:56 TestExpectedResultGenericInference
fn failed[T]() T!Failure => error(Failure("empty"))

fn first() Int! => failed()
// expect-error: MS2001 4:18 unknown type Failure; declare it with 'type Failure:' / 'enum Failure:' / 'interface Failure:', declare it as a type parameter, or import it
// expect-error: MS2001 4:35 unknown binding Failure; declare it with 'Failure := ...' before use, define 'fn Failure(...) T { ... }', or import it from a module
