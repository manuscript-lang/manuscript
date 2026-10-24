# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_suite_header_test.go:24 TestFormatMovesSuiteWithMisindentedHeaderClose
def f() -> Int:
    if a:
        return 1
    elif foo(a):
        return 2

    return 3
