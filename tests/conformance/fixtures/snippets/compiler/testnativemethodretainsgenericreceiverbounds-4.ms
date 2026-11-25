// conform: tags=diagnostics,generics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/builtin_parity_test.go:60 TestNativeMethodRetainsGenericReceiverBounds
fn search[T](values List[T], value T) Bool {
	return values.contains(value: value)
}
// expect-error: MS2001 5:19 unknown or ambiguous member contains on List[T]; contains requires T to be Equal; declare T: Equal on the enclosing function
