# conform: tags=formatter,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_match_lint_test.go:15 TestResultMatchLint
fn use(value: Result[Int, Error]) Int:
    match value:
        ok(n): return n
        error(_): return 0
