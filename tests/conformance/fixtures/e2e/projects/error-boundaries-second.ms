// conform: tags=control-flow,diagnostics,interfaces,interpolation,modules,strings,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/error_boundaries/second.ms
import DomainFailure from "./domain.ms"

export fn second_error(cause DomainFailure) Error {
	return Error(f"second {cause.code}")
}

export fn relay(cause Error) Void! {
	return error(cause)
}
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
