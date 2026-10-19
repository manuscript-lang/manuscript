# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_lambda_comma_test.go:13 TestFormatBlockLambdaFollowedByArgument
fn apply(transform: fn(value: Int) Int, value: Int) Int: transform(value)
fn example() Int:
    return apply(
        transform: fn(value: Int) Int:
            return value - 1
        ,
        value: 3,
    )
