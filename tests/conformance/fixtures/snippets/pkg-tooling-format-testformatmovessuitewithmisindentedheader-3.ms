# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_suite_header_test.go:20 TestFormatMovesSuiteWithMisindentedHeaderClose
def f() -> Int:
    while foo(a):
        if b:
            return 1

        return 2

    return 3
