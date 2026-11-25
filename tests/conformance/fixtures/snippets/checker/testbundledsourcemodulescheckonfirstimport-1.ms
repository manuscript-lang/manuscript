// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/standard_lazy_test.go:29 TestBundledSourceModulesCheckOnFirstImport
fn one() Int {
	return 1
}
// expect-exit: 0
