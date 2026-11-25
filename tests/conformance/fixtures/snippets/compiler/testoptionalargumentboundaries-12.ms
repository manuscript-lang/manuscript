// conform: tags=diagnostics,faults,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:35 TestOptionalArgumentBoundaries
import panic from "@std/core.ms"

fn f[T](value T?) T => return value or panic("called Optional.get() on null")

fn call() Void => value := f(null)
// expect-error: MS3080 8:28 cannot infer type argument T for f; write f[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
