# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
fn use(value: Optional[Int]) Int:
    match value:
        some(Int): return Int
        none: return 0
