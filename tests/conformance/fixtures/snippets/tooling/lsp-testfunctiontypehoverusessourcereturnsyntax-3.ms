# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:26 TestFunctionTypeHoverUsesSourceReturnSyntax
fn identity(callback: fn(Int) Int) fn(Int) Int: callback

fn use(callback: fn(Int) Int) Int: identity(callback)(2)
