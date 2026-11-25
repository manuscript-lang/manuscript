// conform: tags=formatter,interpolation,parser,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/builtin_parity_test.go:9 TestNativeMethodConstraints
fn stringify(value Int) String {
	return f"{value}"
}

fn wrong_label(item Int) String {
	return f"{item}"
}

fn callback() Void {
	return
}
