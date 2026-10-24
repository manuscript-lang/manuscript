# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_test.go:136 TestFormatCommentsAndErrors
# leading
def sum(left: Int, right: Int) -> Int:  # sum
    return left + right  # trailing
