# conform: tags=formatter,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:72 TestNamedArgumentValueContinuation
def use(value: Int) -> Unit:
    return

test "continued argument":
    use(value: 3)
