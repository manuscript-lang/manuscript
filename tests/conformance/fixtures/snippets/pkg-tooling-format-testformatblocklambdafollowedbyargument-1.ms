# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_lambda_comma_test.go:13 TestFormatBlockLambdaFollowedByArgument
def apply(transform: Callable[[Int], Int], value: Int) -> Int: transform(value)

def example() -> Int:
    return apply(transform: lambda (value: Int) -> Int: return value - 1, value: 3)
