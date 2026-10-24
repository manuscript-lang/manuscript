type Box:
    items: List[Int]

impl Box:
    def list() -> List[Int]:
        return self.items

def f() -> List[Int]:
    let b = Box(items: [1])
    return b.list()  # error: only a read-only parameter can
