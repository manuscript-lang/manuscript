// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/position_consumers_test.go:61 TestDocumentSymbolOriginalHeaderAndFieldPositions
// α😀
interface Read {
	fn get() Int
}

type Box {
	value Int  // 😀é
}

fn Box.get() Int {
	return self.value
}

fn neighbor() Int => 1
// expect-exit: 0
