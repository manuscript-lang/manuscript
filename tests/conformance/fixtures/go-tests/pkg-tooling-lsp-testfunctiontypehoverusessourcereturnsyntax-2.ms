# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:20 TestFunctionTypeHoverUsesSourceReturnSyntax
fn apply(callback: fn(value: Int) Int) Int: callback(2)
