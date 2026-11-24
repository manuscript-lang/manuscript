// conform: tags=faults,formatter,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/recursive_types_test.go:9 TestRecursiveFieldsKeepEditorNavigation
import panic from "@std/core.ms"

type Node {
	value Int
	next Node?
}

fn read(node Node) Int {
	return (node.next or panic("called Optional.get() on null")).value
}
