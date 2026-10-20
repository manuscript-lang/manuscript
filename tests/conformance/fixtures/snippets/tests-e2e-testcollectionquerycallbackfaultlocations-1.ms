# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/conversions_queries_test.go:30 TestCollectionQueryCallbackFaultLocations
fn crash(%s) %s:
    return %s
export fn main() Int:
    let values = %s
    let result = values.%s(%s)
    return 0
