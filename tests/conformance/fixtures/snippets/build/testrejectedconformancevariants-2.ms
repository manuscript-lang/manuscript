// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:108 TestRejectedConformanceVariants
fn increase(value Int) Int {
	return value + 1
}
// expect-exit: 0
