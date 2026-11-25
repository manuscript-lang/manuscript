// conform: tags=diagnostics,faults,generics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:43 TestPatternBindingAdvisory
fn use[T](value T?) T {
	match value {
		value => return Value
		null => return panic(message: "empty")
	}
}
// expect-error: MS3000 6:9 binding value shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'
// expect-error: MS2001 6:25 unknown binding Value; did you mean 'value'?
// expect-fix: 6:25-6:30 "value"
// expect-error: MS2001 7:24 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
