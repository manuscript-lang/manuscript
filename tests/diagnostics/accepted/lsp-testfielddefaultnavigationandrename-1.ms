// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/defaults_test.go:81 TestFieldDefaultNavigationAndRename
type Options {
	first Int = 3
	second Int = first + 1
}

fn read() Int => return Options().first
// expect-exit: 0
