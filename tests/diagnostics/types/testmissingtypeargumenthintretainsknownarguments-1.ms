// conform: tags=diagnostics,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/inference_hints_test.go:87 TestMissingTypeArgumentHintRetainsKnownArguments
fn convert[T, U](value T) U? => null

fn first() Void {
	value := convert(1)
}
// expect-error: MS3080 7:14 cannot infer type argument U for convert; write convert[Int, U](...) with an explicit type for U; call arguments and the expected result must determine every type parameter
