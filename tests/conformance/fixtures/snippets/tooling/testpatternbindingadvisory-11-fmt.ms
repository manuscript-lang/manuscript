# conform: tags=alternatives,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/pattern_lint_test.go:42 TestPatternBindingAdvisory
type Failure:
    case NotFound

fn use() Int:
    let NotFound = 1
    return NotFound
