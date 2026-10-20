# conform: tags=interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:654 TestTypeBoundaries
interface Read:
    fn get() Int
fn old(value: Read & Equal) Unit:
    return
