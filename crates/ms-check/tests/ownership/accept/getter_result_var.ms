type Box:
    name: String
    items: List[Int]

impl Box:
    def list() -> List[Int]:
        return self.items

    def pick(first: Bool) -> List[Int]:
        if first:
            return self.items

        return [1]

def borrow_it(var b: Box) -> Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()

def copy_it(var b: Box) -> Int:
    var xs = b.pick(True)
    xs.append(1)
    return b.items.length()
