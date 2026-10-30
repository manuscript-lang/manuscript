import headers from "@std/http.ms"

export fn main() Int:
    let a = headers()
    var b = a  # error: moved
    let _ = b.append("x", "v")
    let _again = a.names()
    return 0
