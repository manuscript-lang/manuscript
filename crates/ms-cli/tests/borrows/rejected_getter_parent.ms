import stdout from "@std/io.ms"

type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn main_body(var b: Box) Int:
    var xs = b.list()
    let n = b.items.length()
    xs.append(n)
    return n

export fn main() Int:
    var b = Box(items: [])
    stdout().write("{main_body(var b)}\n")
    return 0
