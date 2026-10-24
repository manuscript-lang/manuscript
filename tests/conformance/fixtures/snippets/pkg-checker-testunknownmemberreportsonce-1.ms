# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/member_cascade_test.go:16 TestUnknownMemberReportsOnce
def f[T](a: T) -> T:
    return a.foo()
