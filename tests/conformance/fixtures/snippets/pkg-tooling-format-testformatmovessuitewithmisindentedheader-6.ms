# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_suite_header_test.go:25 TestFormatMovesSuiteWithMisindentedHeaderClose
def f() -> Int:
    if a:
        return 1
    elif foo(a):
        return 2

    return 3
