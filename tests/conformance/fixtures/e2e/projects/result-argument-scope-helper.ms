// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/result_argument_scope/helper.ms
export fn erase[T](hold r T!) &T! => r

export fn forward[T](hold r T!) &T! => erase(r)
// expect-exit: 0
