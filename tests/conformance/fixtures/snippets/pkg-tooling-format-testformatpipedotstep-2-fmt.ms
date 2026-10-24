# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_pipe_test.go:23 TestFormatPipeDotStep
def run(n: Int) -> Int:
    let a = n | .size() | try .m() | .k
    return a
