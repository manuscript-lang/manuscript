# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
fn broken(value: Missing) Unit: return

fn empty[T]() T?: none

fn first() Unit:
    let value = empty()
