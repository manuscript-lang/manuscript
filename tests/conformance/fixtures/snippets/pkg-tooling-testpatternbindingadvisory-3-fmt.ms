# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
fn use(value: Optional[Int]) Int:
    match value:
        some(Int): return Int
        none: return 0
