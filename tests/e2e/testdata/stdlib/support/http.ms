import {headers, HttpHeaders} from "@std/http.ms"
import value from "./results.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) -> HttpHeaders:
    let result = headers()

    for name in fields.keys():
        let appended = value(result.append(name, fields.get(name).unwrap().to_bytes()))

    return result

export fn list_headers(fields: Map[String, List[String]]) -> HttpHeaders:
    let result = headers()

    for name in fields.keys():
        for item in fields.get(name).unwrap():
            let appended = value(result.append(name, item.to_bytes()))

    return result
