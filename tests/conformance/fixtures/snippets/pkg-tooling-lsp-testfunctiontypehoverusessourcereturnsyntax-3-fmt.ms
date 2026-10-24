# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:26 TestFunctionTypeHoverUsesSourceReturnSyntax
def identity(callback: Callable[[Int], Int]) -> Callable[[Int], Int]: callback

def use(callback: Callable[[Int], Int]) -> Int: identity(callback)(2)
