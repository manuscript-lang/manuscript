# conform: tags=control-flow,diagnostics,faults,generics,lists,maps,match,modules,stdlib-http,strings,tier-io,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/stdlib/support/http.ms
import headers, HttpHeaders from "@std/net/http.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) HttpHeaders!:
    var result = headers()
    for name in fields.keys():
        let _appended = try (result.append(name, fields.get(name).get()))
    return ok(result)

export fn list_headers(fields: Map[String, List[String]]) HttpHeaders!:
    var result = headers()
    for name in fields.keys():
        for item in fields.get(name).get():
            let _appended = try (result.append(name, item))
    return ok(result)

# Streaming callbacks return plain Error values, so a result from any operation passes through unchanged.
export fn http_result[T](outcome: T!) T!:
    return outcome
