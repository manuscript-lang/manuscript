// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:108 TestRejectedConformanceVariants
fn increase(item Int) Int {
	return item + 1
}
// expect-exit: 0
