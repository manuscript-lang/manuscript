# conform: tags=formatter,generics,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:41 TestExpectedGenericResultEditorConflict
fn identity[T](value: T) T: value

fn first() String: identity(1)

fn second() Int: identity(2)
