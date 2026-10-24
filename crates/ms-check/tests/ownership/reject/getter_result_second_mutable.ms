type Box:
    items: List[Int]

impl Box:
    def list() -> List[Int]:
        return self.items

def f(var b: Box) -> Int:
    var x = b.list()
    var y = b.list()  # error: cannot borrow mutably
    x.append(1)
    return y.length()
