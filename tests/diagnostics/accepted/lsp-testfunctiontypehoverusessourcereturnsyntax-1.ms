// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/function_type_hover_test.go:14 TestFunctionTypeHoverUsesSourceReturnSyntax
fn double(value Int) Int => value * 2

fn run() Int => double(2)
// expect-exit: 0
