# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
fn f() Unit:
    use(fn(value): value + 1)
