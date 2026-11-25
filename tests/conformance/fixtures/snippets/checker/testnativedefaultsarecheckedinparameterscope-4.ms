// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/native_defaults_test.go:18 TestNativeDefaultsAreCheckedInParameterScope
fn f(value Int = value) Int { ... }
// expect-error: MS2001 4:18 unknown binding value; declare it with 'value := ...' before use, define 'fn value(...) T { ... }', or import it from a module
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
