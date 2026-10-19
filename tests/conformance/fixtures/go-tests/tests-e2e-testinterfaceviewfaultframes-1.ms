# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/interface_views_test.go:54 TestInterfaceViewFaultFrames
fn prepare() fn() Int:
    let invalid = 1 / 0
    return fn() Int: 1
export fn main()
