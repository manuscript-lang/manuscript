type Ch:
    buf: List[String]

fn child(var c: Ch) Int:
    c.buf.append("a")
    return 1

fn run(entry: fn(Ch) Int) Int:
    var c = Ch(buf: [])
    return entry(c)

export fn main() Int:
    return run(child) - 1
