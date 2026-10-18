import {headers, HttpHeaders} from "@std/http.ms"

# Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields: Map[String, String]) HttpHeaders:
    let result = headers()
    for name in fields.keys():
        result.append(name, fields.get(name).get().to_bytes()).get()
    return result

export fn list_headers(fields: Map[String, List[String]]) HttpHeaders:
    let result = headers()
    for name in fields.keys():
        for item in fields.get(name).get():
            result.append(name, item.to_bytes()).get()
    return result
