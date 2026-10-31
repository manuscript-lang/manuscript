# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
fn use(value: Int?) Int:
    match value:
        int: return Int
        none: return 0
