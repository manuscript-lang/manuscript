import headers from "@std/net/http.ms"

export fn main() Int:
    a := headers()
    var b = a  // error: moved
    _ := b.append("x", "v")
    _again := a.names()
    return 0
