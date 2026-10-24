# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/helper.ms
export def erase[T](r: Result[T, Error]) -> Result[T, Error]: r

export def forward[T, E: Error](r: Result[T, E]) -> Result[T, Error]: erase(r)
