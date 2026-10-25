type Ch:
    buf: List[String]

def child(var c: Ch) -> Int:
    c.buf.append("a")
    return 1

def run(entry: Callable[[Ch], Int]) -> Int:
    var c = Ch(buf: [])
    return entry(c)

export def main() -> Int:
    return run(child) - 1
