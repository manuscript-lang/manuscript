// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/native_defaults_test.go:76 TestOpaqueNativeConstructorDefaultsStayBounded
type Resource {
	size Int = 1
}
// expect-exit: 0
