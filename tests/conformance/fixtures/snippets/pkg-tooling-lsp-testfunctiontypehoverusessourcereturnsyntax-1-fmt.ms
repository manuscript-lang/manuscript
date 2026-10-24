# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/function_type_hover_test.go:14 TestFunctionTypeHoverUsesSourceReturnSyntax
def double(value: Int) -> Int: value * 2

def run() -> Int: double(2)
