// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_suite_header_test.go:24 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int {
	if a {
		return 1
	} else if foo(a) {
		return 2
	}

	return 3
}
// expect-error: MS2001 5:8 unknown binding a; declare it with 'a := ...' before use, define 'fn a(...) T { ... }', or import it from a module
// expect-error: MS2001 7:15 unknown binding foo; declare it with 'foo := ...' before use, define 'fn foo(...) T { ... }', or import it from a module
