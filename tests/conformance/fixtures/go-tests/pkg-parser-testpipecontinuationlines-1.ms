# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/pipe_test.go:55 TestPipeContinuationLines
fn f() Int:
    let v = x
        | f # first

        # explain
        | g(a: 1)
        .size()
    return 0
