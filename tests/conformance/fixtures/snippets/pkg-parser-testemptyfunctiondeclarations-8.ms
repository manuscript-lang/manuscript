# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:18 TestEmptyFunctionDeclarations
def empty() -> Unit: ...

# empty body
def answer() -> Int: return 3
