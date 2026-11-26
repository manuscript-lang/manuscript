// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/function_type_hover_test.go:20 TestFunctionTypeHoverUsesSourceReturnSyntax
fn apply(callback fn(Int) Int) Int => callback(2)
// expect-exit: 0
