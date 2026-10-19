# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_pipe_test.go:22 TestFormatPipeDotStep
fn run(n: Int) Int:
    let a = n |.size()|try.m()| .k
    return a
