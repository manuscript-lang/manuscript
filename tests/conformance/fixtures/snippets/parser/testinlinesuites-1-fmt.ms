# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
fn f() Unit:
    use(fn value: value + 1)
