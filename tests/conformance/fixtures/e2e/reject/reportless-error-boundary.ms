// conform: tags=testing,tier-core
// conform: phase=check
import panic from "@std/core.ms"

enum DomainError {
	Invalid
}

enum OtherError {
	Rejected
}

fn domain_failure() Int!DomainError {
	return error(DomainError.Invalid)
}

fn common_boundary() Int! {
	return domain_failure()
}

fn propagated_boundary() Int! {
	value := domain_failure()?
	return ok(value)
}

fn unrelated_boundary() Int!OtherError {
	value := domain_failure()?
	return ok(value)
}

fn optional_result(value Int!String?) Int {
	return (value or panic("called Optional.get() on null")).get_or(-1)
}

fn unrelated_optional_error() Int {
	return optional_result(error(7))
}
// expect-error: MS3001 18:12 expected Result[Int, Error], found Result[Int, DomainError] (in the return value)
// expect-error: MS3000 22:14 '?' requires the same error type; this function returns Result[Int, Error] but the operand fails with DomainError, so change the return error type or translate the error with map_error
// expect-error: MS3000 27:14 '?' requires the same error type; this function returns Result[Int, OtherError] but the operand fails with DomainError, so change the return error type or translate the error with map_error
// expect-error: MS3001 36:34 expected String, found Int (in argument 'cause' of error); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 36:34-36:35 "\"7\""
