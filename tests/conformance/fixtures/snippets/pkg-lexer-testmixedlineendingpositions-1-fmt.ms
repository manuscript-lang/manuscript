# conform: tags=control-flow,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/positions_test.go:14 TestMixedLineEndingPositions
# é😀
def value() -> String:
    # comment
    if True:
        return "é😀"

    return ""
