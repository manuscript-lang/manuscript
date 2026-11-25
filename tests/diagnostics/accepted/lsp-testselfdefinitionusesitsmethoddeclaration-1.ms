// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/analysis_test.go:50 TestSelfDefinitionUsesItsMethodDeclaration
interface Read {
	fn get() Int
}

type Box {
	value Int
}

fn Box.get() Int {
	return self.value
}
// expect-exit: 0
