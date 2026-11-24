// conform: tags=control-flow,diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/if_let_test.go:9 TestIfLetBindingReferencesAndRename
fn read(values List[Int]) Int:
	first := values.first()
	if first != null: return first + 1

	return 0
