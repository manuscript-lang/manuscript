# conform: tags=control-flow,faults,formatter,generics,lists,maps,match,modules,parser,stdlib-http,strings,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/support/http.ms
from "@std/http.ms" import headers, HttpHeaders, HttpError

# Explicit fixture migration from the old text maps; no runtime coercion.
export def text_headers(fields: Map[String, String]) -> Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        let appended = try (result.append(name, fields.get(name).get().to_bytes()))
    return ok(result)

export def list_headers(fields: Map[String, List[String]]) -> Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        for item in fields.get(name).get():
            let appended = try (result.append(name, item.to_bytes()))
    return ok(result)

# Streaming callbacks must return HttpError; retain diagnostics from a different operation domain.
export def http_result[T, E: Error](outcome: Result[T, E]) -> Result[T, HttpError]:
    match outcome:
        case ok(found): return ok(found)
        case error(cause): return error(HttpError.Failed(cause.message()))
