# conform: tags=diagnostics,modules,stdlib-encoding,stdlib-json,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:173 TestCommonErrorAcceptsSpecificErrors
import JsonError from "@std/json.ms"
import hex_decode from "@std/encoding.ms"

fn general(cause: JsonError) Error:
    return cause

fn failed() Result[Unit, JsonError]:
    return error(cause: JsonError.InvalidData)

fn forwarded() Result[Unit, Error]:
    return failed()

fn propagated() Result[Unit, Error]:
    let bytes = try hex_decode(text: "zz")
    return ok(value: unit)

fn constructed() Result[Unit, Error]:
    return error(cause: JsonError.InvalidData)
