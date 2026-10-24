# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:102 TestLintOrdersSingleFileFindingsBySourcePosition
def f() -> Int:
    return 0

def g() -> Int:
    let x = 1
    return 2
