import {headers, HttpError, HttpHeaders} from "@std/http.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        try result.append(name, fields.get(name).unwrap().to_bytes())
    return ok(result)

export fn list_headers(fields: Map[String, List[String]]) Result[HttpHeaders, HttpError]:
    let result = headers()
    for name in fields.keys():
        for item in fields.get(name).unwrap():
            try result.append(name, item.to_bytes())
    return ok(result)
