// conform: tags=formatter,interpolation,strings,testing,tier-core
// conform: phase=test,parse
// conform: origin=pkg/tooling/lsp/navigation_test.go:86 TestNativeGenericMethodNavigation
fn label(value Int) String {
	return f"{value}"
}

test "methods" {
	_labels := [1].map(transform: label)
	_convert := [2].map[String]
	_text := " hello ".trim()
}
