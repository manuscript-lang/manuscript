// conform: tags=diagnostics,formatter,generics,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
fn broken(value Missing) Void => return

fn empty[T]() T? => null

fn first() Void {
	value := empty()
}
// expect-error: MS2001 4:17 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
// expect-error: MS3080 9:14 cannot infer type argument T for empty; write empty[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
