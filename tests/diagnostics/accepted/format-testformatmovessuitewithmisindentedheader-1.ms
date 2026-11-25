// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_suite_header_test.go:16 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int {
	for mode in [1] {
		if not (mode == 2) {
			return 2
		}
	}
	return 3
}
// expect-exit: 0
