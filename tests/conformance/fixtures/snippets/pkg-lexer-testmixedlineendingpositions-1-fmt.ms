# conform: tags=control-flow,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/positions_test.go:14 TestMixedLineEndingPositions
# é😀

fn value() String:
    # comment
    if true:
        return "é😀"
    return ""
