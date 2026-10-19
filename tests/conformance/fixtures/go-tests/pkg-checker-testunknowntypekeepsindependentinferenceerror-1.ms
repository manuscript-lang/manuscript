# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
fn broken(value: Missing) Unit: return
fn empty[T]() Optional[T]: none
fn first() Unit:
    let value = empty()
