# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_suite_header_test.go:24 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int:
    if a:
        return 1
    else if foo(
            a
        ):
            return 2
    return 3
