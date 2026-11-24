// conform: tags=diagnostics
// conform: phase=check
import (
	hex_decode from "@std/data/encoding.ms",
	JsonError from "@std/data/json.ms",
)

fn general(cause JsonError) Error {
	return cause
}

fn failed() Result[Void, JsonError] {
	return error(cause: JsonError.InvalidData)
}

fn forwarded() Result[Void, Error] {
	return failed()
}

fn propagated() Result[Void, Error] {
	bytes := hex_decode(text: "zz")?
	return ok(value: void)
}

fn constructed() Result[Void, Error] {
	return error(cause: JsonError.InvalidData)
}
