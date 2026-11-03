import headers, HttpHeaders from "@std/net/http.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) HttpHeaders!:
    var result = headers()
    for name in fields.keys():
        let _appended = try (result.append(name, fields[name]))
    return ok(result)

export fn list_headers(fields: Map[String, List[String]]) HttpHeaders!:
    var result = headers()
    for name in fields.keys():
        for item in fields[name]:
            let _appended = try (result.append(name, item))
    return ok(result)

# Streaming callbacks must fail with a Failed Error; retain the diagnostic text of another operation.
export fn http_result[T](outcome: T!) T!:
    match outcome:
        ok(found): return ok(found)
        error(cause): return error(Error(cause.message.clone(), kind: Failed))
