// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
fn f() Void:
    use(fn value: value + 1)
