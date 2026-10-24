# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_pipe_test.go:22 TestFormatPipeDotStep
def run(n: Int) -> Int:
    let a = n | .size() | try .m() | .k
    return a
