# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/lambda_keyword_test.go:13 TestBlockLambdaCommaDiagnostic
fn before() Int: 0
fn broken() Int:
    return apply(
        op: fn(value: Int) Int:
            return value + 1,
        times: 3
    )
fn after() Int: 2
