# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/member_cascade_test.go:17 TestUnknownMemberReportsOnce
def f() -> Int:
    let x = 1
    let y: Int = x.foo
    return y
