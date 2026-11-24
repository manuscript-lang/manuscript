// conform: tags=formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/inference_hints_test.go:87 TestMissingTypeArgumentHintRetainsKnownArguments
fn convert[T, U](value T) U?: null

fn first() Void:
    value := convert(1)
