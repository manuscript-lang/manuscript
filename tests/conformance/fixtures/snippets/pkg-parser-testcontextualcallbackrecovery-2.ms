# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:227 TestContextualCallbackRecovery
def f() -> Unit:
    use(lambda (value, other: Int): return value + other)
