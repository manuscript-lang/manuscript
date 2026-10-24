type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

    def pick(first: Bool) -> ref List[Int]:
        if first:
            return self.items

        return [1]

def first_of[T](xs: List[T]) -> ref T:
    return xs[0]

def forward(b: Box) -> ref List[Int]:
    return b.list()

def read(b: Box) -> Int:
    let xs = b.list()
    let ys = b.pick(True)
    return xs.length() + ys.length()

def temp(b: Box) -> Int:
    return b.list().length()

def generic(rows: List[List[Int]]) -> Int:
    let row = first_of(rows)
    return row.length()

def chain(b: Box) -> Int:
    let xs = forward(b)
    return xs.length()
