# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:102 TestLintOrdersSingleFileFindingsBySourcePosition
def f() -> Int:
    return 0

def g() -> Int:
    let x = 1
    return 2
