type Box:
    items: List[Int]

impl Box:
    def list() -> List[Int]:
        return self.items

def f(var b: Box) -> Int:
    let xs = b.list()
    b.items = [2]  # error: cannot change `b.items` while `xs` borrows it
    return xs.length()
