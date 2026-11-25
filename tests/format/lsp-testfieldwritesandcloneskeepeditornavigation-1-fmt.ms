// conform: tags=closures,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/mutation_test.go:11 TestFieldWritesAndClonesKeepEditorNavigation
type Val {
	val Int
}

fn work(var value Val) Void {
	callback := fn() Void {
		value.val += 1
	}
	callback()

	copy := value.clone()
	list := [copy]
	list.clone().append(value)
}
// expect-format: unchanged
