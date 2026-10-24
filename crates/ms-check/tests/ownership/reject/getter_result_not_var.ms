type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def f(b: Box) -> Int:
    var xs = b.list()  # error: cannot borrow mutably
    xs.append(1)
    return xs.length()
