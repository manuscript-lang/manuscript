# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/pattern_lint_test.go:42 TestPatternBindingAdvisory
type Failure:
    case NotFound
fn use() Int:
    let NotFound = 1
    return NotFound
