import headers from "@std/net/http.ms"

export fn main() Int:
    var a = headers()
    void a.append("x", "v")
    var b = a.clone()
    void b.append("y", "w")
    return a.names().length() + b.names().length() - 3
