import headers from "@std/http.ms"

export fn main() Int:
    var a = headers()
    let _ = a.append("x", "v")
    var b = a.clone()
    let _ = b.append("y", "w")
    return a.names().length() + b.names().length() - 3
