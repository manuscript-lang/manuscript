// conform: tags=diagnostics,formatter,generics,lists,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/builtin_parity_test.go:45 TestNativeMethodRetainsGenericReceiverBounds
fn search[T Equal](values List[T], value T) Bool {
	return values.contains(value: value)
}
// expect-exit: 0
