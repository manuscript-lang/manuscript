# conform: tags=diagnostics,modules,stdlib-encoding,stdlib-json,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:173 TestCommonErrorAcceptsSpecificErrors
import JsonError from "@std/data/json.ms"
import hex_decode from "@std/data/encoding.ms"

fn general(cause: JsonError) Error:
    return cause

fn failed() Unit!JsonError:
    return error(cause: JsonError.InvalidData)

fn forwarded() Unit!:
    return failed()

fn propagated() Unit!:
    let _bytes = try hex_decode(text: "zz")
    return ok(value: unit)

fn constructed() Unit!:
    return error(cause: JsonError.InvalidData)
