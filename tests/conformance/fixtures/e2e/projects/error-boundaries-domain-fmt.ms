# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/domain.ms
export type DomainFailure:
    code: Int

export type BoxFailure[T]:
    cause: T

export fn box_error[T](box: BoxFailure[T], describe: fn(T) String) Error:
    return Error("box: {describe(box.cause)}")
