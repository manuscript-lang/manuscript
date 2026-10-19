# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:227 TestContextualCallbackRecovery
fn f() Unit:
    use(fn(value, other: Int):
        return value + other
    )
