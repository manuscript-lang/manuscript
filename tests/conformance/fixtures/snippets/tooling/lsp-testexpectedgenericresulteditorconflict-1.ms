// conform: tags=diagnostics,generics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/contextual_generics_test.go:41 TestExpectedGenericResultEditorConflict
fn identity[T](value T) T => value

fn first() String => identity(1)

fn second() Int => identity(2)
// expect-error: MS3001 6:22 expected String, found Int (in the return value); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 6:22-6:33 "f\"{identity(1)}\""
