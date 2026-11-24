// conform: tags=formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
fn broken(value Missing) Void => return

fn empty[T]() T? => null

fn first() Void:
    value := empty()
