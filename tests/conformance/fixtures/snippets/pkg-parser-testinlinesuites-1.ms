# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
def f() -> Unit:
    use(lambda value: value + 1)
