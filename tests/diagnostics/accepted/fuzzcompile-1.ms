// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:280 FuzzCompile
fn f() Int {
	return 1
}
// expect-exit: 0
