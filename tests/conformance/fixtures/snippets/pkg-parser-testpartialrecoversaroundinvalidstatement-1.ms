# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:156 TestPartialRecoversAroundInvalidStatement
fn work(a: Int) Int:
    let b = a + 1
    let c = = 3
    if b > 0:
        let d = )
        let e = b
    return b
