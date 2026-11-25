// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_suite_header_test.go:21 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int {
	while foo(a) {
		if b {
			return 1
		}
		return 2
	}

	return 3
}
// expect-error: MS2001 5:11 unknown binding foo; declare it with 'foo := ...' before use, define 'fn foo(...) T { ... }', or import it from a module
// expect-error: MS2001 6:12 unknown binding b; declare it with 'b := ...' before use, define 'fn b(...) T { ... }', or import it from a module
