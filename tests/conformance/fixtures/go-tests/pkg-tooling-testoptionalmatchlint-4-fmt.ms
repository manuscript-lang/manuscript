# conform: tags=formatter,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/optional_match_lint_test.go:17 TestOptionalMatchLint
fn use(value: Result[Int, Error]) Int:
    return match value:
        ok(n): n
        error(_): 0
