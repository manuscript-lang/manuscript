# conform: tags=control-flow,diagnostics,faults,generics,lists,maps,match,modules,stdlib-http,strings,tier-io,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/stdlib/support/http.ms
import {headers, HttpHeaders, HttpError} from "@std/http.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        let appended = try (result.append(name, fields.get(name).get().to_bytes()))
    return ok(result)

export fn list_headers(fields: Map[String, List[String]]) Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        for item in fields.get(name).get():
            let appended = try (result.append(name, item.to_bytes()))
    return ok(result)

# Streaming callbacks must return HttpError; retain diagnostics from a different operation domain.
export fn http_result[T, E: Error](outcome: Result[T, E]) Result[T, HttpError]:
    match outcome:
        ok(found): return ok(found)
        error(cause): return error(HttpError.Failed(cause.message()))
