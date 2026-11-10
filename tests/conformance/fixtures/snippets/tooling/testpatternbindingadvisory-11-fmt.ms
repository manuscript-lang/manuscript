// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/pattern_lint_test.go:42 TestPatternBindingAdvisory
enum Failure:
    NotFound

fn use() Int:
    NotFound := 1
    return NotFound
