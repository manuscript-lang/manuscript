// conform: tags=closures,mutation,functions,tier-core
// conform: phase=run
// conform: origin=ms-check/tests/messages.rs
type Ch:
    buf: List[String]

fn child(var c: Ch) Int:
    c.buf.append("a")
    return 1

fn run(entry: fn(var Ch) Int) Int:
    var c = Ch(buf: [])
    let n = entry(var c) + entry(var c)
    return n + c.buf.length()

export fn main() Int:
    return run(child) - 4
