# conform: tags=faults,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_match_lint_test.go:17 TestResultMatchLint
fn use(value: Result[Int, Error]) Int:
    return value.get(0)
