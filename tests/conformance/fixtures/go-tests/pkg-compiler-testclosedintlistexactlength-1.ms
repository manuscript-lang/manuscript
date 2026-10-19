# conform: tags=aliasing,control-flow,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:51 TestClosedIntListExactLength
fn probe(flag: Bool) Int:
    let values: List[Int] = []
    var i = 0
    while i < 100:
        
