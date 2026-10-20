# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:26 TestFunctionTypeHoverUsesSourceReturnSyntax
fn identity(callback: fn(value: Int) Int) fn(value: Int) Int: callback
fn use(callback: fn(value: Int) Int) Int: identity(callback)(2)
