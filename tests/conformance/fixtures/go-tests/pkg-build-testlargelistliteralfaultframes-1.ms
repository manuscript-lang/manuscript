# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/lower_large_lists_test.go:28 TestLargeListLiteralFaultFrames
fn value(i: Int) Int: i
fn fail() Int:
    return 1 / 0
export fn main() Int:
    let data = 
