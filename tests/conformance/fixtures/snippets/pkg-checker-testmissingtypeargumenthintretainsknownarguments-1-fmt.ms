# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:87 TestMissingTypeArgumentHintRetainsKnownArguments
def convert[T, U](value: T) -> Optional[U]: none

def first() -> Unit:
    let value = convert(1)
