# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/helper.ms
export fn erase[T](r: T!) T!: r

export fn forward[T](r: T!) T!: erase(r)
