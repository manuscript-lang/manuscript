# conform: tags=diagnostics,generics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:41 TestExpectedGenericResultEditorConflict
def identity[T](value: T) -> T: value

def first() -> String: identity(1)

def second() -> Int: identity(2)
