# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/member_cascade_test.go:18 TestUnknownMemberReportsOnce
def g(v: Int) -> Int:
    return v

def f() -> Int:
    let x = 1
    return g(v: x.foo())
