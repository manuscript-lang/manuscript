# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/diff_test.go:36 TestParseDiffAndReverseApply
fn one() Int:
    let x = 1
    return x

fn two() Int:
    return 2
