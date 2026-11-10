// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_pipe_test.go:6 TestFormatPipeFlow
fn double(n: Int) Int: n * 2

fn run(n: Int) Int:
    a := n | double | double
    b := n
        | double  // first
        // second
        | double
    return a + b
