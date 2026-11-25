// conform: tags=closures,formatter,generics,optional,parser,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/contextual_generics_test.go:10 TestExpectedGenericResultEditorInformation
fn absent[T]() T? => null

fn transform[T, U](move callback fn(T) U) fn(T) U => callback

fn answer() Void {
	_empty Int? := absent()
	_callback fn(Int) String := transform(item => item.to_string())
}
