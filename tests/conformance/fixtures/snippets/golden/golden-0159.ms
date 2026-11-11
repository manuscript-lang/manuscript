// conform: tags=diagnostics
// conform: phase=check
import JsonError from "@std/data/json.ms"
import hex_decode from "@std/data/encoding.ms"
fn general(cause: JsonError) Error:
    return cause
fn failed() Result[Unit, JsonError]:
    return error(cause: JsonError.InvalidData)
fn forwarded() Result[Unit, Error]:
    return failed()
fn propagated() Result[Unit, Error]:
    bytes := hex_decode(text: "zz")?
    return ok(value: unit)
fn constructed() Result[Unit, Error]:
    return error(cause: JsonError.InvalidData)
