# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:87 TestMissingTypeArgumentHintRetainsKnownArguments
fn convert[T, U](value: T) Optional[U]: none

fn first() Unit:
    let value = convert(1)
