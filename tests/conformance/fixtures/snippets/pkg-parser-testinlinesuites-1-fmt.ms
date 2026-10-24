# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
def f() -> Unit:
    use(lambda value: value + 1)
