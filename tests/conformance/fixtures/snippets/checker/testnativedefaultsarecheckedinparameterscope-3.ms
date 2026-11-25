// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/native_defaults_test.go:17 TestNativeDefaultsAreCheckedInParameterScope
fn f(first Int = second, second Int = 1) Int { ... }
// expect-error: MS2001 4:18 unknown binding second; declare it with 'second := ...' before use, define 'fn second(...) T { ... }', or import it from a module
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
