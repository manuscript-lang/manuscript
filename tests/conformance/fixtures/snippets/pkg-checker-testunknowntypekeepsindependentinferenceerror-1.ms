# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
def broken(value: Missing) -> Unit: return

def empty[T]() -> Optional[T]: none

def first() -> Unit:
    let value = empty()
