// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
fn example() Void {
	choose(first: () => "a", second: () => "b", other: () => missing)
}
// expect-error: MS2001 5:5 unknown binding choose; declare it with 'choose := ...' before use, define 'fn choose(...) T { ... }', or import it from a module
