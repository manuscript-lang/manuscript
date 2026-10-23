# conform: tags=closures,diagnostics,generics,optional,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:10 TestExpectedGenericResultEditorInformation
fn absent[T]() Optional[T]: none

fn transform[T, U](callback: fn(value: T) U) fn(value: T) U: callback

fn answer() Unit:
    let empty: Optional[Int] = absent()
    let callback: fn(value: Int) String = transform(fn(item): item.to_string())
