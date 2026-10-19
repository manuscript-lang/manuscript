# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/views_test.go:43 TestViewDepthCycleAndErrors
fn a(n: Int) Int:
    return b(n)

fn b(n: Int) Int:
    return a(n)
