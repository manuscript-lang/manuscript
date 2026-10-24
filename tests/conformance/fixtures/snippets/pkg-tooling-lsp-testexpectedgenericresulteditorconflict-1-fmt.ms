# conform: tags=formatter,generics,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:41 TestExpectedGenericResultEditorConflict
def identity[T](value: T) -> T: value

def first() -> String: identity(1)

def second() -> Int: identity(2)
