# conform: tags=control-flow,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_match_lint_test.go:16 TestResultMatchLint
def use(value: Result[Int, Error]) -> Int:
    if let n = value:
        return n

    return 0
