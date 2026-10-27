from "@std/io.ms" import stdout

type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def main_body(var b: Box) -> Int:
    var xs = b.list()
    let n = b.items.length()
    xs.append(n)
    return n

export def main() -> Int:
    var b = Box(items: [])
    let _ = stdout().write(f"{main_body(var b)}\n")
    return 0
