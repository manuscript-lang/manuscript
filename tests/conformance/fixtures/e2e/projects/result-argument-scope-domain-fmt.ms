# conform: tags=formatter,generics,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/domain.ms
export type Cause[T]:
    value: T

export def make() -> Cause[Int]: Cause(7)
