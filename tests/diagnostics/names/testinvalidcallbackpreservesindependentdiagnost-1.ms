// conform: tags=closures,diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/callbacks_test.go:121 TestInvalidCallbackPreservesIndependentDiagnostics
fn example() Void {
	names := [1, 2].map(item => missing).join(other_missing)
	conflict := apply(value: 1, transform: fn(item String) => missing_result)
	wrong Int := "text"
	callback fn(Int) Int := () => missing_too
}
// expect-error: MS2001 5:33 unknown binding missing; declare it with 'missing := ...' before use, define 'fn missing(...) T { ... }', or import it from a module
// expect-error: MS2001 5:47 unknown binding other_missing; declare it with 'other_missing := ...' before use, define 'fn other_missing(...) T { ... }', or import it from a module
// expect-error: MS2001 6:17 unknown binding apply; declare it with 'apply := ...' before use, define 'fn apply(...) T { ... }', or import it from a module
// expect-error: MS3001 7:18 expected Int, found String (in the initializer of 'wrong')
// expect-error: MS3000 8:29 callback parameter count does not match its context; the context expects 1 parameter, found 0, so write exactly the parameters its context declares
// expect-error: MS2001 8:35 unknown binding missing_too; declare it with 'missing_too := ...' before use, define 'fn missing_too(...) T { ... }', or import it from a module
