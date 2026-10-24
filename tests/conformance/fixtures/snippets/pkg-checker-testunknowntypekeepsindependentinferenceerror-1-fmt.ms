# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:101 TestUnknownTypeKeepsIndependentInferenceError
def broken(value: Missing) -> Unit: return

def empty[T]() -> Optional[T]: none

def first() -> Unit:
    let value = empty()
