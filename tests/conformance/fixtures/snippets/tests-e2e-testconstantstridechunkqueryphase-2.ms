# conform: tags=control-flow,lists,mutation,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/counter_chunk_test.go:29 TestConstantStrideChunkQueryPhase
fn probe%d(visits: List[Int]) Int:
    var sum = 0
    var i = %d
    with resource = Resource(visits):
        while i < %d:
            sum += 3
            i += 1
    return sum
