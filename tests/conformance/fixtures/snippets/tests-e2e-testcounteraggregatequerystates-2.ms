# conform: tags=control-flow,lists,mutation,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/counter_aggregate_test.go:65 TestCounterAggregateQueryStates
fn %s(visits: List[Int], scoped: Bool) Int:
    %s
    var i = %d
    if scoped:
        with resource = AggregateResource(visits):
            while i < %d:
                %s
                i += 1
    else:
        while i < %d:
            %s
            i += 1
    return %s
