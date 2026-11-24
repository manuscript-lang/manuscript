// conform: tags=diagnostics,generics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
fn broken(value Missing) Void => return

fn empty[T]() T? => null

fn first() Void:
    value := empty()
