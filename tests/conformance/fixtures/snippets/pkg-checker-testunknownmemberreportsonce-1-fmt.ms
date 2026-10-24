# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/member_cascade_test.go:16 TestUnknownMemberReportsOnce
def f[T](a: T) -> T:
    return a.foo()
