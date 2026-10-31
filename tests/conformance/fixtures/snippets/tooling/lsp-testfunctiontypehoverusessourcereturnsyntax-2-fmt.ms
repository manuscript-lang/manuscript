# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:20 TestFunctionTypeHoverUsesSourceReturnSyntax
fn apply(callback: fn(Int) Int) Int: callback(2)
