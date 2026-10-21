# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:195 TestPartialRecoversAroundUnterminatedDelimiter
fn add(a: Int, b: Int) Int:
    return a + b

export fn main() Int:
    let s = add(a: 1, b: 2)
    let q = 
