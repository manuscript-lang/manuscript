# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:18 TestEmptyFunctionDeclarations
fn empty() Unit:
# empty body
fn answer() Int: return 3
