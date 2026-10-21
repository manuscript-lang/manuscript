# conform: tags=control-flow,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/positions_test.go:14 TestMixedLineEndingPositions
# é😀

fn value() String:
    # comment
    if true:
        return "é😀"
    return ""
