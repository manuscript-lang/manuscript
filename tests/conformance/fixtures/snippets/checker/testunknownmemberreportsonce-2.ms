// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/member_cascade_test.go:17 TestUnknownMemberReportsOnce
fn f() Int:
    x := 1
    y: Int = x.foo
    return y
