# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_suite_header_test.go:25 TestFormatMovesSuiteWithMisindentedHeaderClose
fn f() Int:
    if a:
        return 1
    else if foo(a):
        return 2

    return 3
