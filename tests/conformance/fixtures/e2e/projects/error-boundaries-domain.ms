// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/testdata/projects/error_boundaries/domain.ms
export type DomainFailure {
	code Int
}

export type BoxFailure[T] {
	cause T
}

export fn box_error[T](box BoxFailure[T], describe fn(T) String) Error {
	return Error(f"box: {describe(box.cause)}")
}
// expect-exit: 0
