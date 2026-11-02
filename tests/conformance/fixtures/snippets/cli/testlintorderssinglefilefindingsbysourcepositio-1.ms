# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:102 TestLintOrdersSingleFileFindingsBySourcePosition
fn f() Int:
    return 0

fn g() Int:
    let _x = 1
    return 2
