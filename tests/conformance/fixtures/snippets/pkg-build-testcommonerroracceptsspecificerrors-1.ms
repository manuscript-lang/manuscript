# conform: tags=diagnostics,modules,stdlib-encoding,stdlib-json,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:173 TestCommonErrorAcceptsSpecificErrors
from "@std/json.ms" import JsonError
from "@std/encoding.ms" import hex_decode

def general(cause: JsonError) -> Error:
    return cause

def failed() -> Result[Unit, JsonError]:
    return error(cause: JsonError.InvalidData)

def forwarded() -> Result[Unit, Error]:
    return failed()

def propagated() -> Result[Unit, Error]:
    let _bytes = try hex_decode(text: "zz")
    return ok(value: ())

def constructed() -> Result[Unit, Error]:
    return error(cause: JsonError.InvalidData)
