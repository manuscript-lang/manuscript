type Box:
    name: String
    items: List[Int]
    spare: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

    def pick(first: Bool) -> ref List[Int]:
        if first:
            return self.items

        return self.spare

def borrow_it(var b: Box) -> Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()

def copy_it(var b: Box) -> Int:
    var xs = b.pick(True).clone()
    xs.append(1)
    return b.items.length()
