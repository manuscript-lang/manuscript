# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:239 TestContextualCallbackRecovery
fn f(transform: fn(value) Int) Unit: return
