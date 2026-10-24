# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:227 TestContextualCallbackRecovery
def f() -> Unit:
    use(lambda (value, other: Int): return value + other)
