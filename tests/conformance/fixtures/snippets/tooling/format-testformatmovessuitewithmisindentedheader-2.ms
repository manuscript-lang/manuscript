# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_suite_header_test.go:17 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int:
    for mode in [1]:
        if not (mode == 2):
            return 2
    return 3
