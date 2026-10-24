# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/member_cascade_test.go:17 TestUnknownMemberReportsOnce
def f() -> Int:
    let x = 1
    let y: Int = x.foo
    return y
