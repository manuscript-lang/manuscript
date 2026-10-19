# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_pipe_test.go:7 TestFormatPipeFlow
fn double(n: Int) Int: n * 2

fn run(n: Int) Int:
    let a = n | double | double
    let b = n
        | double  # first
        # second
        | double
    return a + b
