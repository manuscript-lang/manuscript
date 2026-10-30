# conform: tags=closures,diagnostics,generics,optional,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:10 TestExpectedGenericResultEditorInformation
fn absent[T]() T?: none

fn transform[T, U](callback: fn(T) U) fn(T) U: callback

fn answer() Unit:
    let _empty: Int? = absent()
    let _callback: fn(Int) String = transform(fn item: item.to_string())
