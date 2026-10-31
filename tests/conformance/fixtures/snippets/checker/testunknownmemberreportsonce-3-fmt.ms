# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/member_cascade_test.go:18 TestUnknownMemberReportsOnce
fn g(v: Int) Int:
    return v

fn f() Int:
    let x = 1
    return g(v: x.foo())
