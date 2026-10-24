# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_suite_header_test.go:21 TestFormatMovesSuiteWithMisindentedHeaderClose
def f() -> Int:
    while foo(a):
        if b:
            return 1

        return 2

    return 3
