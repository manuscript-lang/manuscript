# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:18 TestEmptyFunctionDeclarations
def empty() -> Unit: ...

# empty body
def answer() -> Int: return 3
