type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def f(var b: Box) -> Int:
    var xs = b.list()
    let n = b.items.length()  # error: cannot use `b.items` while `xs`
    xs.append(n)
    return n
