# conform: tags=control-flow,lists,mutation,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/builder_range_test.go:54 TestBuilderAndRangeQueryStates
fn %s(visits: List[Int], scoped: Bool) Int:
    let values: List[Int] = [%s]
    var sum = 0
    if scoped:
        with resource = Resource(visits):
            for x in values:
                sum %s x
    else:
        for x in values:
            sum %s x
    return sum
