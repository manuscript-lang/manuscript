# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/format/format_pipe_test.go:23 TestFormatPipeDotStep
fn run(n: Int) Int:
    let a = n | .size() | try .m() | .k
    return a
