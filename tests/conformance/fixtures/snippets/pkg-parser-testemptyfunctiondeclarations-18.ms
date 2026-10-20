# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:40 TestEmptyFunctionDeclarations
fn f(callback: fn(value: Int = 3) Int) Unit: return unit
