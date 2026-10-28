# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:227 TestContextualCallbackRecovery
fn f() Unit:
    use(fn(value, other: Int): return value + other)
