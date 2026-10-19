# conform: tags=aliasing,control-flow,lists,mutation,parser,strings,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/builder_range_test.go:34 TestBuilderAndRangeQueryStates
fn %s(visits: List[Int], scoped: Bool) String:
    let b = StringBuilder()
    var i = 0
    if scoped:
        with resource = Resource(visits):
            while i < %d:
                %s
    else:
        while i < %d:
            b.append(%s)
            i += 1
    return b.freeze()
