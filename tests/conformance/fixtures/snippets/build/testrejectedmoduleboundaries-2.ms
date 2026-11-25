// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:406 TestRejectedModuleBoundaries
export fn value() Int {
	return 1
}
// expect-exit: 0
