type Box:
    items: List[Int]
    other: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def trimmed(line: String) -> ref String:
    return line.trim()

def len(line: String) -> Int:
    let t = trimmed(line)
    return t.length()

def grow(b: Box) -> Int:
    let xs = b.items
    return xs.length()
