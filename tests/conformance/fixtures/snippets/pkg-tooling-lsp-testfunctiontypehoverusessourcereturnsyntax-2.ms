# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:20 TestFunctionTypeHoverUsesSourceReturnSyntax
def apply(callback: Callable[[Int], Int]) -> Int: callback(2)
