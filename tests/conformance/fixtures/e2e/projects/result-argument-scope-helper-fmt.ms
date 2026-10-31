# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/helper.ms
export fn erase[T](r: T!) T!: r

export fn forward[T, E: Error](r: T!E) T!: erase(r)
